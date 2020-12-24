Require Import Lia Datatypes PeanoNat Compare_dec Framework TotalMem FSParameters Log Log.Specs.
Require Import DiskLayer CryptoDiskLayer CacheLayer CachedDiskLayer.
Require Import FunctionalExtensionality.

(** Cache uses disk addresses but its functions take data region addresses 
    and converts them to disk addresses to use *)
Local Fixpoint write_batch_to_cache al vl :=
  match al, vl with
  | a::al', v::vl' =>
    _ <- |CDCO| Write a v;
    write_batch_to_cache al' vl'           
  | _, _ => Ret tt
 end.

Definition Forall_dec {A} (P: A -> Prop) (P_dec: forall a: A, {P a}+{~P a}):
  forall l: list A, {Forall P l}+{~Forall P l}.
induction l; simpl; eauto.  
destruct (P_dec a), IHl;
eauto.
- right; intros.
  intros Hx; inversion Hx; eauto.
- right; intros.
  intros Hx; inversion Hx; eauto.
- right; intros.
  intros Hx; inversion Hx; eauto.
Defined.

(* Converts to disk address before writing to log *)
Definition write  addr_l (data_l: list value) :=
  if (Forall_dec (fun a => a < data_length) (fun a => lt_dec a data_length) addr_l) then
    if (NoDup_dec addr_l) then
      if (Nat.eq_dec (length addr_l) (length data_l)) then
        if (le_dec (length (addr_list_to_blocks (map (plus data_start) addr_l)) + length data_l) log_length) then
          
          committed <- |CDDP| commit (addr_list_to_blocks (map (plus data_start) addr_l)) data_l;
        _ <-
        if committed then
          Ret tt
        else
          _ <- |CDDP| apply_log;
        _ <- |CDCO| (Flush _ _);
        _ <- |CDDP| commit (addr_list_to_blocks (map (plus data_start) addr_l)) data_l;
        Ret tt;
        
        write_batch_to_cache (map (plus data_start) addr_l) data_l
        else
          Ret tt
      else
        Ret tt
    else
      Ret tt
  else
    Ret tt.


(* Takes a data region_address *)
Definition read a :=
  if lt_dec a data_length then
    mv <- |CDCO| Read _ (data_start + a);
  match mv with
  | Some v =>
    Ret v
  | None =>
  |CDDP| |DO| DiskLayer.Read (data_start + a)
  end
  else
    Ret value0.

Local Fixpoint write_lists_to_cache l_al_vl :=
  match l_al_vl with
  | nil =>
    Ret tt
  | al_vl :: l =>
    _ <- write_batch_to_cache (fst al_vl) (snd al_vl);
    write_lists_to_cache l
  end.

Definition recover :=
  _ <- |CDCO| (Flush _ _);
  log <- |CDDP| recover;
  write_lists_to_cache log.

(** Representation Invariants **) 
Inductive Cached_Log_Crash_State:=
| During_Commit (old_merged_disk new_merged_disk : @total_mem addr addr_dec value) : Cached_Log_Crash_State
| After_Commit (new_merged_disk : @total_mem addr addr_dec value) : Cached_Log_Crash_State
| During_Apply (merged_disk : @total_mem addr addr_dec value) : Cached_Log_Crash_State
| After_Apply (merged_disk : @total_mem addr addr_dec value) : Cached_Log_Crash_State
| During_Recovery (merged_disk : @total_mem addr addr_dec value) : Cached_Log_Crash_State.

Definition cached_log_rep merged_disk (s: Language.state CachedDiskLang) :=
  exists txns,
    fst s = Mem.list_upd_batch empty_mem (map addr_list txns) (map data_blocks txns) /\
    log_rep txns (snd s) /\
    merged_disk = total_mem_map fst (shift (plus data_start) (list_upd_batch_set (snd (snd s)) (map addr_list txns) (map data_blocks txns))).

Definition cached_log_crash_rep cached_log_crash_state (s: Language.state CachedDiskLang) :=
  match cached_log_crash_state with
  | During_Commit old_merged_disk new_merged_disk =>
    (exists txns,
       log_crash_rep (During_Commit_Log_Write txns) (snd s) /\
       old_merged_disk = total_mem_map fst (shift (plus data_start)
       (list_upd_batch (sync (snd (snd s))) (map addr_list txns)
                       (map (map (fun vs => (vs, []))) (map data_blocks txns))))) \/
    (exists old_txns txns,
       log_crash_rep (During_Commit_Header_Write old_txns txns) (snd s) /\
       new_merged_disk = total_mem_map fst (shift (plus data_start)
        (list_upd_batch (sync (snd (snd s))) (map addr_list txns)
          (map (map (fun vs => (vs, []))) (map data_blocks txns)))) /\
       old_merged_disk = total_mem_map fst (shift (plus data_start)
        (list_upd_batch (sync (snd (snd s))) (map addr_list old_txns)
                        (map (map (fun vs => (vs, []))) (map data_blocks old_txns)))))
  | After_Commit new_merged_disk =>
    exists txns,
    log_rep txns (snd s) /\
     new_merged_disk = total_mem_map fst (shift (plus data_start)
        (list_upd_batch (sync (snd (snd s))) (map addr_list txns)
                        (map (map (fun vs => (vs, []))) (map data_blocks txns))))

  | During_Apply merged_disk =>
    exists txns,
    log_crash_rep (Log.During_Apply txns) (snd s) /\
     merged_disk = total_mem_map fst (shift (plus data_start)
        (list_upd_batch (sync (snd (snd s))) (map addr_list txns)
                        (map (map (fun vs => (vs, []))) (map data_blocks txns))))

  | After_Apply merged_disk =>
    log_rep [] (snd s) /\
      merged_disk = total_mem_map fst (shift (plus data_start) (snd (snd s)))
   
  | During_Recovery merged_disk =>
    exists txns,
    log_crash_rep (Log.During_Recovery txns) (snd s) /\
    merged_disk = total_mem_map fst (shift (plus data_start)
        (list_upd_batch_set (snd (snd s)) (map addr_list txns)
                            (map data_blocks txns)))
    end.

Definition cached_log_reboot_rep merged_disk (s: Language.state CachedDiskLang) :=
  exists txns,
    log_reboot_rep txns (snd s) /\
    merged_disk = total_mem_map fst (shift (plus data_start) (list_upd_batch_set (snd (snd s)) (map addr_list txns) (map data_blocks txns))).


Set Nested Proofs Allowed.


(*** SPECS ***)
Global Opaque Log.commit Log.apply_log.
Theorem write_batch_to_cache_finished:
  forall al vl o s s' t u,
    length al = length vl ->
    exec CachedDiskLang u o s (write_batch_to_cache al vl) (Finished s' t) ->
    snd s' = snd s /\
    fst s' = Mem.upd_batch (fst s) al vl.
Proof.
  induction al; simpl; intros;
  repeat invert_exec; cleanup;
  eauto; simpl in *; try lia.
  repeat invert_exec.
  edestruct IHal; eauto.
Qed.


Theorem write_batch_to_cache_crashed:
  forall al vl o s s' u,
    exec CachedDiskLang u o s (write_batch_to_cache al vl) (Crashed s') ->
    snd s' = snd s.
Proof.
  induction al; simpl; intros;
  repeat invert_exec; cleanup;
  eauto; simpl in *; try lia;
  invert_exec; eauto.
  split_ors; cleanup; repeat invert_exec; eauto.
  eapply IHal in H0; cleanup; eauto.
Qed.

Theorem write_lists_to_cache_finished:
  forall l_la_lv s o s' t u,
    Forall (fun la_lv => length (fst la_lv) = length (snd la_lv)) l_la_lv ->
    exec CachedDiskLang u o s (write_lists_to_cache l_la_lv) (Finished s' t) ->
    fst s' = Mem.list_upd_batch (fst s) (map fst l_la_lv) (map snd l_la_lv) /\
    snd s' = snd s.
Proof.
  induction l_la_lv; simpl; intros; repeat invert_exec; eauto.
  inversion H; cleanup.
  apply write_batch_to_cache_finished in H0; eauto.
  cleanup.
  apply IHl_la_lv in H1; eauto.
  cleanup; repeat cleanup_pairs; eauto.
Qed.  
  

Theorem write_lists_to_cache_crashed:
  forall l_la_lv s o s' u,
    Forall (fun la_lv => length (fst la_lv) = length (snd la_lv)) l_la_lv ->
    exec CachedDiskLang u o s (write_lists_to_cache l_la_lv) (Crashed s') ->
    snd s' = snd s.
Proof.
  induction l_la_lv; simpl; intros; repeat invert_exec; eauto.
  split_ors; cleanup; repeat invert_exec.
  apply write_batch_to_cache_crashed in H0; eauto.

  inversion H; cleanup.
  apply write_batch_to_cache_finished in H0; eauto.
  apply IHl_la_lv in H1; eauto.
  cleanup; repeat cleanup_pairs; eauto.
Qed.

Theorem read_finished:
  forall merged_disk a s o s' t u,
    cached_log_rep merged_disk s ->
    exec CachedDiskLang u o s (read a) (Finished s' t) ->
    ((exists v, 
    merged_disk a = v /\
    t = v /\
    a < data_length) \/
    (a >= data_length /\ t = value0)) /\
    s' = s.
Proof.
  unfold read; simpl; intros; repeat invert_exec; eauto.
  cleanup; repeat invert_exec; eauto.
  {
    unfold cached_log_rep in *; cleanup.
    
    eapply equal_f in H.
    rewrite H in H7.
    eapply Mem.list_upd_batch_some in H7.
    unfold empty_mem in *; split_ors; try congruence.
    
    eexists.
    rewrite total_mem_map_shift_comm.
    rewrite shift_some.
    rewrite total_mem_map_fst_list_upd_batch_set.
    intuition eauto.
    (** we need a connection between mem and total mem. **)
    admit.
    destruct s; simpl; eauto.
    repeat rewrite map_length; eauto.
    {
      eapply forall_forall2.
      apply Forall_forall; intros.
      rewrite <- combine_map in H1.
      apply in_map_iff in H1; cleanup; simpl.

      unfold log_rep, log_rep_general, log_rep_explicit in *;
      simpl in *; logic_clean.
      unfold log_rep_inner, txns_valid in *; logic_clean.
      
      eapply Forall_forall in H10; eauto.
      unfold txn_well_formed in H10; logic_clean.
      rewrite H13 in *.
      apply firstn_length_l; eauto; lia.
      repeat rewrite map_length; eauto.
    }
  }

  {
    simpl in *.
    unfold cached_log_rep in *; cleanup.
    eapply equal_f in H.
    setoid_rewrite H7 in H.
    symmetry in H; eapply list_upd_batch_none in H.
    logic_clean.
    eexists.
    rewrite total_mem_map_shift_comm.
    rewrite shift_some.
    rewrite total_mem_map_fst_list_upd_batch_set.
    rewrite list_upd_batch_not_in; eauto.
    unfold total_mem_map; simpl.
    simpl in *; intuition eauto.
    repeat cleanup_pairs; eauto.
    destruct s1; eauto.
    {
    eapply forall_forall2.
    apply Forall_forall; intros.
    rewrite <- combine_map in H1.
    apply in_map_iff in H1; cleanup; simpl.

     unfold log_rep, log_rep_general, log_rep_explicit in *;
     simpl in *; logic_clean.
     unfold log_rep_inner, txns_valid in *; logic_clean.
     
     eapply Forall_forall in H11; eauto.
     unfold txn_well_formed in H11; logic_clean.
     rewrite H14 in *.
     apply firstn_length_l; eauto; lia.
     repeat rewrite map_length; eauto.
    }
  }
  intuition eauto.
  right; split; eauto; lia.
  Unshelve.
  exact empty_mem.
Admitted.

Theorem read_crashed:
  forall a s o s' u,
    exec CachedDiskLang u o s (read a) (Crashed s') ->
    s' = s.
Proof.
  unfold read; simpl; intros; cleanup; repeat invert_exec; eauto.
  split_ors; cleanup; repeat invert_exec.
  destruct s; eauto.
  cleanup; repeat invert_exec;
  repeat cleanup_pairs; eauto.
  destruct s1; eauto.
Qed.


Lemma recover_finished:  
  forall merged_disk s o s' t u,
  cached_log_reboot_rep merged_disk s ->
  exec CachedDiskLang u o s recover (Finished s' t) ->
  cached_log_rep merged_disk s'.
Proof.
  unfold recover, cached_log_reboot_rep; intros; cleanup.
  repeat invert_exec.
  eapply recover_finished in H5; eauto.
  apply write_lists_to_cache_finished in H3.
  repeat cleanup_pairs.
  unfold cached_log_rep; simpl; eexists; intuition eauto.
  rewrite map_fst_combine, map_snd_combine by (repeat rewrite map_length; eauto); eauto.
  assert (A: map addr_list x = map (map (Init.Nat.add data_start)) (map (map (fun a => a - data_start)) (map addr_list x))). {
    repeat rewrite map_map.
    apply map_ext_in.
    intros.
    rewrite map_map.
    rewrite map_noop; eauto.
    intros.
    unfold log_rep, log_rep_general, log_rep_explicit, log_rep_inner, txns_valid in *; simpl in *; cleanup.
    eapply Forall_forall in H11; eauto.
    unfold txn_well_formed in H11; simpl in *; cleanup.
    eapply Forall_forall in H15; eauto; lia.
  }
  rewrite A at 2.
  rewrite shift_list_upd_batch_set_comm.
  rewrite shift_eq_after with (m1:=s2)(m2:=sync s3).
  rewrite <- shift_list_upd_batch_set_comm.
  rewrite <- A.

  repeat (rewrite total_mem_map_shift_comm, total_mem_map_fst_list_upd_batch_set);
  rewrite total_mem_map_fst_sync_noop; eauto.
  {
    unfold sumbool_agree; intros; intuition eauto.
    destruct (addr_dec x0 y); subst.
    destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
    destruct (addr_dec (data_start + x0) (data_start + y)); eauto; lia.
  }
  {
    intros; lia.
  }
  {
    intros; apply H7; lia.
  }
  {
    unfold sumbool_agree; intros; intuition eauto.
    destruct (addr_dec x0 y); subst.
    destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
    destruct (addr_dec (data_start + x0) (data_start + y)); eauto; lia.
  }
  {
    cleanup.
    rewrite Forall_forall; intros.
    rewrite <- combine_map in H1.
    apply in_map_iff in H1; cleanup; simpl.
    unfold log_rep, log_rep_general, log_rep_explicit, log_rep_inner, txns_valid in *; simpl in *; cleanup.
    eapply Forall_forall in H14; eauto.
    unfold txn_well_formed in H14; simpl in *; cleanup.
    apply firstn_length_l; eauto.
  }
Qed.

Lemma recover_crashed:  
  forall merged_disk s o s' u,
  cached_log_reboot_rep merged_disk s ->
  exec CachedDiskLang u o s recover (Crashed s') ->
  (cached_log_reboot_rep merged_disk s' \/
  cached_log_crash_rep (During_Recovery merged_disk) s' \/
  cached_log_crash_rep (After_Commit merged_disk) s') /\
  ((forall a, a >= data_start -> snd (snd s') a = snd (snd s) a) \/
     (forall a, a >= data_start -> snd (snd s') a = sync (snd (snd s)) a)) .
Proof.
  unfold recover, cached_log_reboot_rep; intros; cleanup.
  repeat invert_exec.
  split_ors; cleanup; repeat invert_exec.
  repeat cleanup_pairs; eauto.
  intuition eauto.
  split_ors; cleanup; repeat invert_exec.
  {
    eapply recover_crashed in H4; eauto.
    repeat cleanup_pairs.
    split_ors; cleanup.
    {
      intuition eauto.
      left; eexists; intuition eauto.
      assert (A: map addr_list x = map (map (Init.Nat.add data_start)) (map (map (fun a => a - data_start)) (map addr_list x))). {
    repeat rewrite map_map.
    apply map_ext_in.
    intros.
    rewrite map_map.
    rewrite map_noop; eauto.
    intros.
    unfold log_reboot_rep, log_rep_general, log_rep_explicit, log_rep_inner, txns_valid in *; simpl in *; cleanup.
    eapply Forall_forall in H21; eauto.
    unfold txn_well_formed in H21; simpl in *; cleanup_no_match.
    eapply Forall_forall in H24; eauto; lia.
      }
      rewrite A at 2.
      rewrite shift_list_upd_batch_set_comm.
      rewrite shift_eq_after with (m1:=s2)(m2:=s3).
      rewrite <- shift_list_upd_batch_set_comm.
      rewrite <- A; eauto.
      {
        unfold sumbool_agree; intros; intuition eauto.
        destruct (addr_dec x0 y); subst.
        destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
        destruct (addr_dec (data_start + x0) (data_start + y)); eauto; lia.
      }
      {
        intros; lia.
      }
      {
        intros; apply H1; lia.
      }
      {
        unfold sumbool_agree; intros; intuition eauto.
        destruct (addr_dec x0 y); subst.
        destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
        destruct (addr_dec (data_start + x0) (data_start + y)); eauto; lia.
      }
    }
    split_ors; cleanup.
    {
      intuition eauto.
      right; left; eexists; intuition eauto.
      assert (A: map addr_list x =
                 map (map (Init.Nat.add data_start))
                     (map (map (fun a => a - data_start)) (map addr_list x))). {
        repeat rewrite map_map.
        apply map_ext_in.
        intros.
        rewrite map_map.
        rewrite map_noop; eauto.
        intros.
        unfold log_reboot_rep, log_rep_general, log_rep_explicit,
        log_rep_inner, txns_valid in *; simpl in *; cleanup.
        eapply Forall_forall in H12; eauto.
        unfold txn_well_formed in H12; simpl in *; cleanup_no_match.
        eapply Forall_forall in H16; eauto; lia.
      }
      rewrite A at 2.
      rewrite shift_list_upd_batch_set_comm.
      rewrite shift_eq_after with (m1:=s2)(m2:=s3).
      rewrite <- shift_list_upd_batch_set_comm.
      rewrite <- A; eauto.
      
      {
        unfold sumbool_agree; intros; intuition eauto.
        destruct (addr_dec x0 y); subst.
        destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
        destruct (addr_dec (data_start + x0) (data_start + y)); eauto; lia.
      }
      {
        intros; lia.
      }
      {
        intros; apply H1; lia.
      }
      {
        unfold sumbool_agree; intros; intuition eauto.
        destruct (addr_dec x0 y); subst.
        destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
        destruct (addr_dec (data_start + x0) (data_start + y)); eauto; lia.
      }
    }
    intuition eauto.
    left; eexists; intuition eauto.
    {
      unfold log_rep, log_rep_general, log_reboot_rep in *.
      cleanup.
      do 4 eexists; intuition eauto; congruence.
    }
    assert (A: map addr_list x =
               map (map (Init.Nat.add data_start))
                   (map (map (fun a => a - data_start)) (map addr_list x))). {
      repeat rewrite map_map.
      apply map_ext_in.
      intros.
      rewrite map_map.
      rewrite map_noop; eauto.
      intros.
      unfold log_rep, log_rep_general, log_rep_explicit,
      log_rep_inner, txns_valid in *; simpl in *; cleanup.
      eapply Forall_forall in H11; eauto.
      unfold txn_well_formed in H11; simpl in *; cleanup_no_match.
      eapply Forall_forall in H15; eauto; lia.
    }
    
    rewrite A at 2.
    rewrite shift_list_upd_batch_set_comm.
    rewrite shift_eq_after with (m1:=s2)(m2:=sync s3).
    rewrite <- shift_list_upd_batch_set_comm.
    rewrite <- A; eauto.
    repeat rewrite total_mem_map_shift_comm.
    repeat rewrite total_mem_map_fst_list_upd_batch_set.
    rewrite total_mem_map_fst_sync_noop; eauto.
    
    {
      unfold sumbool_agree; intros; intuition eauto.
      destruct (addr_dec x0 y); subst.
      destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
      destruct (addr_dec (data_start + x0) (data_start + y)); eauto; lia.
    }
    {
      intros; lia.
    }
    {
      intros; apply H1; lia.
    }
    {
      unfold sumbool_agree; intros; intuition eauto.
      destruct (addr_dec x0 y); subst.
      destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
      destruct (addr_dec (data_start + x0) (data_start + y)); eauto; lia.
    } 
  }
  {
    eapply Log.Specs.recover_finished in H5; eauto; cleanup.
    apply write_lists_to_cache_crashed in H3; cleanup.
    repeat cleanup_pairs.
    {
      intuition eauto.
      right; right; eexists; intuition eauto.
    {
      unfold log_rep, log_rep_general, log_reboot_rep in *.
      cleanup.
      assert (A: map addr_list x =
                 map (map (Init.Nat.add data_start))
                     (map (map (fun a => a - data_start)) (map addr_list x))). {
        repeat rewrite map_map.
        apply map_ext_in.
        intros.
        rewrite map_map.
        rewrite map_noop; eauto.
        intros.
        unfold log_rep, log_rep_general, log_rep_explicit,
        log_rep_inner, txns_valid in *; simpl in *; cleanup_no_match.
        eapply Forall_forall in H12; eauto.
        unfold txn_well_formed in H12; simpl in *; cleanup_no_match.
        eapply Forall_forall in H23; eauto; lia.
      }
    
      rewrite <- sync_list_upd_batch_set.
      rewrite <- sync_shift_comm.
      rewrite A at 2.
      rewrite shift_list_upd_batch_set_comm.
      rewrite shift_eq_after with (m1:=s3)(m2:=sync s4).
      rewrite <- shift_list_upd_batch_set_comm.
      rewrite <- A; eauto.
      rewrite total_mem_map_fst_sync_noop.
      repeat rewrite total_mem_map_shift_comm.
      repeat rewrite total_mem_map_fst_list_upd_batch_set.
      rewrite total_mem_map_fst_sync_noop; eauto.
      
      {
        unfold sumbool_agree; intros; intuition eauto.
        destruct (addr_dec x9 y); subst.
        destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
        destruct (addr_dec (data_start + x9) (data_start + y)); eauto; lia.
      }
      {
        intros; lia.
      }
      {
        intros; apply H7; lia.
      }
      {
        unfold sumbool_agree; intros; intuition eauto.
        destruct (addr_dec x9 y); subst.
        destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
        destruct (addr_dec (data_start + x9) (data_start + y)); eauto; lia.
      }
    }
    }
    {
      apply Forall_forall; intros.
      rewrite <- combine_map in H1.
      apply in_map_iff in H1; cleanup; simpl.
      unfold log_reboot_rep, log_rep_explicit, log_rep_inner, txns_valid in H;
      simpl in *; logic_clean.
      eapply Forall_forall in H15; eauto.
      unfold txn_well_formed in H15; logic_clean.
      rewrite H18.
      apply firstn_length_l; eauto.
      lia.
    }
  }
Qed.
  
Theorem write_finished:
  forall merged_disk s o al vl s' t u,
  cached_log_rep merged_disk s ->
  exec CachedDiskLang u o s (write al vl) (Finished s' t) ->
  cached_log_rep merged_disk s' \/
  (cached_log_rep (upd_batch merged_disk al vl) s' /\
   Forall (fun a => a < data_length) al).
Proof.
  unfold write; simpl; intros.
  cleanup; simpl in *; invert_exec_no_match; simpl in *; cleanup_no_match; simpl in *; eauto.
  invert_exec.
  unfold cached_log_rep in *; logic_clean.
  destruct (addr_list_to_blocks_to_addr_list (map (Init.Nat.add data_start) al)).
  unfold log_rep in *; logic_clean.
  eapply commit_finished in H3; eauto.
  all: try rewrite H6.
  split_ors; cleanup_no_match.
  {(** initial commit is success **)
    right.
    repeat invert_exec.
    apply write_batch_to_cache_finished in H1; eauto; cleanup.
    repeat cleanup_pairs.
    split; eauto.
    exists (x4++[x7]).
    simpl.
    repeat rewrite map_app; simpl.
    
    unfold log_rep, log_rep_general, log_rep_explicit,
    log_rep_inner, txns_valid in *; cleanup; simpl in *.
    eapply_fresh forall_app_l in H11. 
    inversion Hx; simpl in *; cleanup.
    unfold txn_well_formed in H20; cleanup.
    rewrite firstn_app2; eauto.
    simpl; intuition eauto.
    {
      rewrite Mem.list_upd_batch_app; eauto.
      repeat rewrite map_length; eauto.
    }
    {
      do 3 eexists; intuition eauto.
    }
    {
      assert (A: map addr_list x4 ++ [map (Init.Nat.add data_start) al] =
                 map (map (Nat.add data_start)) (map (map (fun a => a - data_start)) (map addr_list x4) ++ [al])). {
        repeat rewrite map_map; simpl.
        rewrite map_app; simpl.
        repeat rewrite map_map.
        setoid_rewrite map_ext_in at 3.
        eauto.
        intros.
        rewrite map_map.        
        setoid_rewrite map_ext_in.
        apply map_id.
        intros; simpl.
        eapply Forall_forall in H11; eauto.
        unfold txn_well_formed in H11; logic_clean.
        eapply Forall_forall in H34; eauto; lia.
        
      }
      setoid_rewrite A.
      rewrite shift_list_upd_batch_set_comm; eauto.
      setoid_rewrite shift_eq_after with (m1:= s0) (m2:= sync s3); intros; try lia.
      rewrite <- shift_list_upd_batch_set_comm; eauto.      
      rewrite <- A.

      repeat rewrite total_mem_map_shift_comm.
      repeat rewrite total_mem_map_fst_list_upd_batch_set.
      rewrite total_mem_map_fst_sync_noop.
      rewrite list_upd_batch_app; simpl.
      rewrite shift_upd_batch_comm; eauto.
      {
        unfold sumbool_agree; intros; intuition eauto.
        destruct (addr_dec x y); subst.
        destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
        destruct (addr_dec (data_start + x) (data_start + y)); eauto; lia.
      }
      {
        repeat rewrite map_length; eauto.
      }
      {
        unfold sumbool_agree; intros; intuition eauto.
        destruct (addr_dec x y); subst.
        destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
        destruct (addr_dec (data_start + x) (data_start + y)); eauto; lia.
      }
      {
        apply H10; lia.
      }
      {
        unfold sumbool_agree; intros; intuition eauto.
        destruct (addr_dec x y); subst.
        destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
        destruct (addr_dec (data_start + x) (data_start + y)); eauto; lia.
      }
    }
    rewrite map_length; eauto.
    rewrite map_length; eauto.
  }
  {(** First commit failed. Time to apply the log **)
    repeat invert_exec.
    simpl in *.
    repeat cleanup_pairs; simpl in *.
    eapply apply_log_finished in H9; eauto.
    logic_clean.
    apply write_batch_to_cache_finished in H1.
    logic_clean.
    unfold log_rep in *; logic_clean.
    eapply commit_finished in H10; eauto.
    all: try rewrite H6.
    split_ors; cleanup_no_match.
    {(** second commit is success **)
    right.
    repeat cleanup_pairs.
    split; eauto.
    exists ([x1]).
    simpl.
    
    unfold log_rep, log_rep_general, log_rep_explicit,
    log_rep_inner, txns_valid in *; cleanup; simpl in *. 
    inversion H14; simpl in *; cleanup.
    unfold txn_well_formed in H2; cleanup.
    rewrite firstn_app2; eauto.
    unfold log_header_block_rep in *; simpl in *; cleanup.
    simpl; intuition eauto.
    {
      do 3 eexists; intuition eauto.
    }
    {
      rewrite shift_upd_batch_set_comm.
      setoid_rewrite shift_eq_after with (m1:= s2) (m2:= sync
          (sync
             (upd_set (list_upd_batch_set s0 (map addr_list x4) (map data_blocks x4)) hdr_block_num
                      (encode_header (update_hdr (decode_header (fst (s0 hdr_block_num))) header_part0))))); intros; try lia.
      rewrite sync_idempotent.
      rewrite total_mem_map_fst_upd_batch_set.
      repeat rewrite total_mem_map_shift_comm.
      rewrite total_mem_map_fst_sync_noop.
      rewrite total_mem_map_fst_upd_set.
      repeat rewrite total_mem_map_fst_list_upd_batch_set.
      rewrite shift_upd_noop; eauto.

      {
        pose proof data_start_where_log_ends.
        pose proof hdr_before_log.
        lia.
      }
      {
        eapply H12; lia.
      }
      {
        unfold sumbool_agree; intros; intuition eauto.
        destruct (addr_dec x0 y); subst.
        destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
        destruct (addr_dec (data_start + x0) (data_start + y)); eauto; lia.
      }
    }
    rewrite map_length; eauto.
    }
    {
      rewrite app_length in H10.
      repeat cleanup_pairs.
      unfold log_rep, log_rep_general, log_rep_explicit,
      log_rep_inner, header_part_is_valid, txns_valid in *;
      simpl in *; cleanup; simpl in *. 
          
      rewrite <- H11 in *; simpl in *.
      lia.
    }
    {
      rewrite firstn_app2; eauto.
      apply FinFun.Injective_map_NoDup; eauto.
      unfold FinFun.Injective; intros; lia.
      rewrite map_length; eauto.
    }
    {
      rewrite firstn_app2; eauto.    
      apply Forall_forall; intros.
      apply in_map_iff in H7; cleanup.
      eapply_fresh Forall_forall in f; eauto.
      pose proof data_fits_in_disk.
      split; try lia.
      rewrite map_length; eauto.
    }    
    {
      rewrite app_length, map_length; lia.
    }
    {
      rewrite map_length; eauto.
    }
  }
  {
    rewrite firstn_app2; eauto.
    apply FinFun.Injective_map_NoDup; eauto.
    unfold FinFun.Injective; intros; lia.
    rewrite map_length; eauto.
  }
  {
    rewrite firstn_app2; eauto.    
    apply Forall_forall; intros.
    apply in_map_iff in H7; cleanup_no_match.
    eapply_fresh Forall_forall in f; eauto.
    pose proof data_fits_in_disk.
    split; try lia.
    rewrite map_length; eauto.
  }
  {
    rewrite app_length, map_length; lia.
  }
Qed.


Theorem write_crashed:
  forall merged_disk s o al vl s' u,
  cached_log_rep merged_disk s ->
  exec CachedDiskLang u o s (write al vl) (Crashed s') ->
  cached_log_rep merged_disk s' \/
  cached_log_crash_rep (During_Commit merged_disk (upd_batch merged_disk al vl)) s' \/
  cached_log_crash_rep (After_Commit (upd_batch merged_disk al vl)) s' \/
  cached_log_crash_rep (During_Apply merged_disk) s' \/
  cached_log_crash_rep (After_Apply merged_disk) s'.
Proof.
  unfold cached_log_rep, write; simpl; intros.
  cleanup; invert_exec.
  {
    split_ors; cleanup; repeat invert_exec.
    {
      destruct (addr_list_to_blocks_to_addr_list (map (Init.Nat.add data_start) al)).
      eapply commit_crashed in H3; eauto.
      {
        repeat (split_ors; cleanup);
        repeat cleanup_pairs; eauto.
        {
          right; left; unfold cached_log_crash_rep; simpl.
          left; eexists; intuition eauto.
          rewrite <- sync_list_upd_batch_set.
          rewrite <- sync_shift_comm.
          
          assert (A: map addr_list x =
                     map (map (Init.Nat.add data_start)) (map (map (fun a => a - data_start)) (map addr_list x))). {
            repeat rewrite map_map; simpl.
            setoid_rewrite map_ext_in at 2.
            eauto.
            intros.
            rewrite map_map.        
            setoid_rewrite map_ext_in.
            apply map_id.
            intros; simpl.
            unfold log_crash_rep, log_rep_inner, txns_valid in *; cleanup.
            
            eapply Forall_forall in H13; eauto.
            unfold txn_well_formed, record_is_valid in H13; logic_clean.
            eapply Forall_forall in H18; eauto; lia.
          }
          rewrite A.
          repeat rewrite shift_list_upd_batch_set_comm.
          replace (shift (Init.Nat.add data_start) s3) with (shift (Init.Nat.add data_start) s2); eauto.
          {
            apply shift_eq_after.
            intros; lia.
            intros; apply H3; lia.
          }
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x0 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x0) (data_start + y)); eauto; lia.
          }
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x0 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x0) (data_start + y)); eauto; lia.
          }
        }
        {
          right; left; unfold cached_log_crash_rep; simpl.
          right; do 2 eexists; intuition eauto.
          {
            rewrite <- sync_list_upd_batch_set.
            rewrite <- sync_shift_comm.
            
            assert (A: map addr_list (x++[x0]) =
                       map (map (Init.Nat.add data_start))
                           (map (map (fun a => a - data_start))
                                (map addr_list (x++[x0])))). {
              repeat rewrite map_map; simpl.
              setoid_rewrite map_ext_in at 2.
              eauto.
            intros.
            rewrite map_map.        
            setoid_rewrite map_ext_in.
            apply map_id.
            intros; simpl.
            unfold log_crash_rep, log_rep_inner, txns_valid in *; cleanup.
            
            eapply Forall_forall in H19; eauto.
            unfold txn_well_formed, record_is_valid in H19; logic_clean.
            eapply Forall_forall in H24; eauto; lia.
          }
          assert (A0: map addr_list x =
                      map (map (Init.Nat.add data_start))
                          (map (map (fun a => a - data_start))
                               (map addr_list x))). {
            repeat rewrite map_map; simpl.
            setoid_rewrite map_ext_in at 2.
            eauto.
            intros.
            rewrite map_map.        
            setoid_rewrite map_ext_in.
            apply map_id.
            intros; simpl.
            unfold log_crash_rep, log_rep_inner, txns_valid in *; cleanup.
            
            eapply Forall_forall in H19; eauto.
            unfold txn_well_formed, record_is_valid in H19; logic_clean.
            eapply Forall_forall in H24; eauto; lia.
          }
          rewrite A, A0.
          repeat rewrite shift_list_upd_batch_set_comm.
          replace (shift (Init.Nat.add data_start) s3) with (shift (Init.Nat.add data_start) s2); eauto.
          
          repeat rewrite map_app.
          rewrite list_upd_batch_set_app; simpl.
          rewrite total_mem_map_fst_sync_noop.
          rewrite total_mem_map_fst_upd_batch_set.
          unfold log_crash_rep in *; simpl in *; logic_clean.
          unfold log_rep_inner, txns_valid in H12; logic_clean.
          eapply forall_app_l in H15.
          simpl in *.
          inversion H15; subst.
          unfold txn_well_formed in H18; logic_clean.
          rewrite H20, H0, H4 in *.
          rewrite firstn_app2.
          replace (map (fun a : nat => a - data_start) (map (Init.Nat.add data_start) al)) with al; eauto.

          {
            rewrite map_map.        
            setoid_rewrite map_ext_in.
            rewrite map_id; eauto.
            intros; simpl.
            lia.
          }
          rewrite map_length; eauto.
          repeat rewrite map_length; eauto.
          
          apply shift_eq_after.
          intros; lia.
          intros; apply H6; lia.
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x4 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x4) (data_start + y)); eauto; lia.
          }
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x4 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x4) (data_start + y)); eauto; lia.
          }
          }
          {
           rewrite <- sync_list_upd_batch_set.
           rewrite <- sync_shift_comm.
           
           assert (A0: map addr_list x =
                       map (map (Init.Nat.add data_start))
                           (map (map (fun a => a - data_start))
                                (map addr_list x))). {
            repeat rewrite map_map; simpl.
            setoid_rewrite map_ext_in at 2.
            eauto.
            intros.
            rewrite map_map.        
            setoid_rewrite map_ext_in.
            apply map_id.
            intros; simpl.
            unfold log_crash_rep, log_rep_inner, txns_valid in *; cleanup.
            
            eapply Forall_forall in H19; eauto.
            unfold txn_well_formed, record_is_valid in H19; logic_clean.
            eapply Forall_forall in H24; eauto; lia.
          }
          rewrite A0.
          repeat rewrite shift_list_upd_batch_set_comm.
          replace (shift (Init.Nat.add data_start) s3) with (shift (Init.Nat.add data_start) s2); eauto.
          
          repeat rewrite map_app.

          apply shift_eq_after.
          intros; lia.
          intros; apply H6; lia.
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x4 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x4) (data_start + y)); eauto; lia.
          }
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x4 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x4) (data_start + y)); eauto; lia.
          }
          }
        }

        {
          right; right; left; unfold cached_log_crash_rep; simpl.
          eexists; intuition eauto.
          
          rewrite <- sync_list_upd_batch_set.
          rewrite <- sync_shift_comm.
          
          assert (A: map addr_list (x++[x0]) =
                     map (map (Init.Nat.add data_start))
                         (map (map (fun a => a - data_start))
                              (map addr_list (x++[x0])))). {
            repeat rewrite map_map; simpl.
            setoid_rewrite map_ext_in at 2.
            eauto.
            intros.
            rewrite map_map.        
            setoid_rewrite map_ext_in.
            apply map_id.
            intros; simpl.
            unfold log_rep, log_rep_general, log_rep_explicit,
            log_rep_inner, txns_valid in *; cleanup.
            
            eapply Forall_forall in H13; eauto.
            unfold txn_well_formed, record_is_valid in H13; logic_clean.
            eapply Forall_forall in H24; eauto; lia.
          }
          rewrite A.
          repeat rewrite shift_list_upd_batch_set_comm.
          replace (shift (Init.Nat.add data_start) s2) with (shift (Init.Nat.add data_start) (sync s3)); eauto.

          rewrite <- shift_list_upd_batch_set_comm, <- A.
          rewrite <- total_mem_map_fst_upd_batch_set.
          rewrite <- shift_upd_batch_set_comm.
          
          repeat rewrite map_app.
          rewrite list_upd_batch_set_app; simpl.
          rewrite total_mem_map_fst_sync_noop.
          repeat rewrite total_mem_map_shift_comm.
          repeat rewrite total_mem_map_fst_upd_batch_set.
          repeat rewrite total_mem_map_fst_list_upd_batch_set.
          rewrite total_mem_map_fst_sync_noop; eauto.
          
          unfold log_rep, log_rep_general, log_rep_explicit in *;
          simpl in *; logic_clean.
          unfold log_rep_inner, txns_valid in *; logic_clean.
          eapply forall_app_l in H17.
          simpl in *.
          inversion H17; subst.
          unfold txn_well_formed in H22; logic_clean.
          rewrite H21, H0, H4 in *.
          rewrite firstn_app2; eauto.
          rewrite map_length; eauto.
          repeat rewrite map_length; eauto.
          
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x4 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x4) (data_start + y)); eauto; lia.
          }
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x4 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x4) (data_start + y)); eauto; lia.
          }          
          {
            apply shift_eq_after.
            intros; lia.
            intros; rewrite H6; eauto; lia.
          }
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x4 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x4) (data_start + y)); eauto; lia.
          }
        }
      }
      all: try rewrite H4, firstn_app2.
      all: try rewrite app_length;
      try rewrite map_length; try lia.
      {
        apply FinFun.Injective_map_NoDup; eauto.
        unfold FinFun.Injective; intros; lia.
      }
      {
        apply Forall_forall; intros.
        apply in_map_iff in H5; cleanup_no_match.
        eapply_fresh Forall_forall in f; eauto.
        pose proof data_fits_in_disk.
        split; try lia.
      }
      {
        rewrite H4, app_length, map_length; lia.
      }
    }
    {
      unfold log_rep in *; logic_clean.
      destruct (addr_list_to_blocks_to_addr_list (map (Init.Nat.add data_start) al)).
      eapply commit_finished in H4; eauto.
      split_ors; cleanup; try congruence.
      {
        split_ors; cleanup; repeat invert_exec;
        repeat cleanup_pairs.
        {
          right; right; left; unfold cached_log_crash_rep; simpl.
          eexists; intuition eauto.
          
          rewrite <- sync_list_upd_batch_set.
          rewrite <- sync_shift_comm.
          
          assert (A: map addr_list (x++[x3]) =
                     map (map (Init.Nat.add data_start))
                         (map (map (fun a => a - data_start))
                              (map addr_list (x++[x3])))). {
            repeat rewrite map_map; simpl.
            setoid_rewrite map_ext_in at 2.
            eauto.
            intros.
            rewrite map_map.        
            setoid_rewrite map_ext_in.
            apply map_id.
            intros; simpl.
            unfold log_rep, log_rep_general, log_rep_explicit,
            log_rep_inner, txns_valid in *; cleanup.
            
            eapply Forall_forall in H13; eauto.
            unfold txn_well_formed, record_is_valid in H13; logic_clean.
            eapply Forall_forall in H24; eauto; lia.
          }
          rewrite A.
          repeat rewrite shift_list_upd_batch_set_comm.
          replace (shift (Init.Nat.add data_start) s2) with (shift (Init.Nat.add data_start) (sync s3)); eauto.

          rewrite <- shift_list_upd_batch_set_comm, <- A.
          rewrite <- total_mem_map_fst_upd_batch_set.
          rewrite <- shift_upd_batch_set_comm.
          
          repeat rewrite map_app.
          rewrite list_upd_batch_set_app; simpl.
          rewrite total_mem_map_fst_sync_noop.
          repeat rewrite total_mem_map_shift_comm.
          repeat rewrite total_mem_map_fst_upd_batch_set.
          repeat rewrite total_mem_map_fst_list_upd_batch_set.
          rewrite total_mem_map_fst_sync_noop; eauto.
          
          unfold log_rep, log_rep_general, log_rep_explicit in *;
          simpl in *; logic_clean.
          unfold log_rep_inner, txns_valid in *; logic_clean.
          eapply forall_app_l in H17.
          simpl in *.
          inversion H17; subst.
          unfold txn_well_formed in H22; logic_clean.
          rewrite H21, H4, H1 in *.
          rewrite firstn_app2; eauto.
          rewrite map_length; eauto.
          repeat rewrite map_length; eauto.
          
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x2 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x2) (data_start + y)); eauto; lia.
          }
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x2 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x2) (data_start + y)); eauto; lia.
          }          
          {
            apply shift_eq_after.
            intros; lia.
            intros; rewrite H8; eauto; lia.
          }
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x2 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x2) (data_start + y)); eauto; lia.
          }
        }
        {
          eapply write_batch_to_cache_crashed in H5.
          simpl in *; cleanup.
          right; right; left; unfold cached_log_crash_rep; simpl.
          eexists; intuition eauto.
          
          rewrite <- sync_list_upd_batch_set.
          rewrite <- sync_shift_comm.
          
          assert (A: map addr_list (x++[x3]) =
                     map (map (Init.Nat.add data_start))
                         (map (map (fun a => a - data_start))
                              (map addr_list (x++[x3])))). {
            repeat rewrite map_map; simpl.
            setoid_rewrite map_ext_in at 2.
            eauto.
            intros.
            rewrite map_map.        
            setoid_rewrite map_ext_in.
            apply map_id.
            intros; simpl.
            unfold log_rep, log_rep_general, log_rep_explicit,
            log_rep_inner, txns_valid in *; cleanup.
            
            eapply Forall_forall in H14; eauto.
            unfold txn_well_formed, record_is_valid in H14; logic_clean.
            eapply Forall_forall in H25; eauto; lia.
          }
          rewrite A.
          repeat rewrite shift_list_upd_batch_set_comm.
          replace (shift (Init.Nat.add data_start) s2) with (shift (Init.Nat.add data_start) (sync s3)); eauto.

          rewrite <- shift_list_upd_batch_set_comm, <- A.
          rewrite <- total_mem_map_fst_upd_batch_set.
          rewrite <- shift_upd_batch_set_comm.
          
          repeat rewrite map_app.
          rewrite list_upd_batch_set_app; simpl.
          rewrite total_mem_map_fst_sync_noop.
          repeat rewrite total_mem_map_shift_comm.
          repeat rewrite total_mem_map_fst_upd_batch_set.
          repeat rewrite total_mem_map_fst_list_upd_batch_set.
          rewrite total_mem_map_fst_sync_noop; eauto.
          
          unfold log_rep, log_rep_general, log_rep_explicit in *;
          simpl in *; logic_clean.
          unfold log_rep_inner, txns_valid in *; logic_clean.
          eapply forall_app_l in H18.
          simpl in *.
          inversion H18; subst.
          unfold txn_well_formed in H23; logic_clean.
          rewrite H22, H4, H1 in *.
          rewrite firstn_app2; eauto.
          rewrite map_length; eauto.
          repeat rewrite map_length; eauto.
          
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x2 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x2) (data_start + y)); eauto; lia.
          }
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x2 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x2) (data_start + y)); eauto; lia.
          }          
          {
            apply shift_eq_after.
            intros; lia.
            intros; rewrite H8; eauto; lia.
          }
          {
            unfold sumbool_agree; intros; intuition eauto.
            destruct (addr_dec x2 y); subst.
            destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
            destruct (addr_dec (data_start + x2) (data_start + y)); eauto; lia.
          }
        }
      }
      all: try rewrite H1, firstn_app2.
      all: try rewrite app_length;
      try rewrite map_length; try lia.
      {
        apply FinFun.Injective_map_NoDup; eauto.
        unfold FinFun.Injective; intros; lia.
      }
      {
        apply Forall_forall; intros.
        apply in_map_iff in H2; cleanup_no_match.
        eapply_fresh Forall_forall in f; eauto.
        pose proof data_fits_in_disk.
        split; try lia.
      }
      {
        rewrite H1, app_length, map_length; lia.
      }
    }
    {
      unfold log_rep in *; logic_clean.
      eapply commit_finished in H4; eauto.
      {
        split_ors; cleanup; try congruence.
        repeat cleanup_pairs.
        split_ors; cleanup; repeat invert_exec.
        {
          split_ors; cleanup; repeat invert_exec.
          {(** Apply log crahed **)
            simpl in *;
            eapply apply_log_crashed in H2; eauto.
            cleanup; split_ors; cleanup; repeat cleanup_pairs.
             {
               left; unfold cached_log_rep; simpl.
               eexists; intuition eauto.
             }
             {               
               split_ors; cleanup.
               {
                 left; unfold cached_log_rep; simpl.
                 eexists; intuition eauto.
                 repeat rewrite total_mem_map_shift_comm.
                 repeat rewrite total_mem_map_fst_list_upd_batch_set.
                 rewrite total_mem_map_fst_upd_batch_set.
                 rewrite total_mem_map_fst_list_upd_batch_set.
                 rewrite upd_batch_to_list_upd_batch_singleton.
                 setoid_rewrite <- list_upd_batch_app at 2.
                 unfold log_rep_general, log_rep_explicit, log_rep_inner, txns_valid in *; logic_clean.
                 rewrite <- H9.
                 erewrite RepImplications.bimap_get_addr_list.
                 4: eauto.
                 rewrite list_upd_batch_firstn_noop; eauto.
                 {
                   apply forall_forall2.
                   apply Forall_forall; intros.
                   rewrite <- combine_map in H11.
                   apply in_map_iff in H11; cleanup.
                   simpl.
                   eapply Forall_forall in H10; eauto.
                   unfold txn_well_formed in H10; logic_clean.
                   rewrite H13.
                   apply firstn_length_l; eauto.
                   lia.
                   repeat rewrite map_length; eauto.
                 }
                 eauto.
                 rewrite map_length; eauto.
                 unfold log_rep_general, log_rep_explicit, log_rep_inner, txns_valid in *; logic_clean.
                 rewrite <- H9.                 
                 erewrite RepImplications.bimap_get_addr_list.
                 repeat rewrite firstn_length, map_length; eauto.
                 3: eauto.
                 eauto.
                 rewrite map_length; eauto.
               }
               split_ors; cleanup.
               {
                 left; unfold cached_log_rep; simpl.
                 eexists; intuition eauto.
                 repeat rewrite total_mem_map_shift_comm.
                 repeat rewrite total_mem_map_fst_list_upd_batch_set.
                 rewrite total_mem_map_fst_sync_noop.
                 rewrite total_mem_map_fst_list_upd_batch_set.
                 unfold log_rep_general, log_rep_explicit, log_rep_inner, txns_valid in *; logic_clean.
                 rewrite <- H9.
                 erewrite RepImplications.bimap_get_addr_list.
                 4: eauto.
                 rewrite list_upd_batch_noop; eauto.
                 {
                   apply forall_forall2.
                   apply Forall_forall; intros.
                   rewrite <- combine_map in H11.
                   apply in_map_iff in H11; cleanup.
                   simpl.
                   eapply Forall_forall in H10; eauto.
                   unfold txn_well_formed in H10; logic_clean.
                   rewrite H13.
                   apply firstn_length_l; eauto.
                   lia.
                   repeat rewrite map_length; eauto.
                 }
                 {
                   apply forall_forall2.
                   apply Forall_forall; intros.
                   rewrite <- combine_map in H11.
                   apply in_map_iff in H11; cleanup.
                   simpl.
                   eapply Forall_forall in H10; eauto.
                   unfold txn_well_formed in H10; logic_clean.
                   rewrite H13.
                   apply firstn_length_l; eauto.
                   lia.
                   repeat rewrite map_length; eauto.
                 }
                 eauto.
                 rewrite map_length; eauto.
               }
               {
                 simpl in *.
                 cleanup; simpl in *.
                 right; right; right; left; unfold cached_log_rep; simpl in *.
                 eexists; intuition eauto.
                 
                 repeat rewrite total_mem_map_shift_comm.
                 rewrite <- sync_list_upd_batch_set.
                 rewrite total_mem_map_fst_sync_noop.
                 repeat rewrite total_mem_map_fst_list_upd_batch_set.
                 rewrite total_mem_map_fst_upd_set.
                 rewrite total_mem_map_fst_sync_noop.
                 rewrite total_mem_map_fst_list_upd_batch_set.
                 setoid_rewrite <- shift_upd_noop at 6.
                 rewrite upd_list_upd_batch_upd_noop.
                 setoid_rewrite shift_upd_noop.
                 unfold log_rep_general, log_rep_explicit, log_rep_inner, txns_valid in *; simpl in *; logic_clean.
                 rewrite <- H9.
                 erewrite RepImplications.bimap_get_addr_list.
                 4: eauto.
                 rewrite list_upd_batch_noop; eauto.

                 {
                   apply forall_forall2.
                   apply Forall_forall; intros.
                   rewrite <- combine_map in H11.
                   apply in_map_iff in H11; cleanup.
                   simpl.
                   eapply Forall_forall in H10; eauto.
                   unfold txn_well_formed in H10; logic_clean.
                   rewrite H13.
                   apply firstn_length_l; eauto.
                   lia.
                   repeat rewrite map_length; eauto.
                 }
                 {
                   apply forall_forall2.
                   apply Forall_forall; intros.
                   rewrite <- combine_map in H11.
                   apply in_map_iff in H11; cleanup.
                   simpl.
                   eapply Forall_forall in H10; eauto.
                   unfold txn_well_formed in H10; logic_clean.
                   rewrite H13.
                   apply firstn_length_l; eauto.
                   lia.
                   repeat rewrite map_length; eauto.
                 }
                 eauto.
                 rewrite map_length; eauto.
                 {
                   intros; pose proof hdr_before_log.
                   pose proof data_start_where_log_ends.
                   lia.
                 }
                 {                   
                   unfold log_rep_general, log_rep_explicit, log_rep_inner, txns_valid in *; logic_clean.
                   apply forall_forall2.
                   apply Forall_forall; intros.
                   rewrite <- combine_map in H11.
                   apply in_map_iff in H11; cleanup.
                   simpl.
                   eapply Forall_forall in H10; eauto.
                   unfold txn_well_formed in H10; logic_clean.
                   rewrite H13.
                   apply firstn_length_l; eauto.
                   lia.
                   repeat rewrite map_length; eauto.
                 }
                 {
                   intros; pose proof hdr_before_log.
                   pose proof data_start_where_log_ends.
                   lia.
                 }
               }
             }
          }
          eapply apply_log_finished in H3; eauto.
          simpl in *; cleanup.
          repeat cleanup_pairs.
          split_ors; cleanup.
          {(** Flush Crashed **)
            repeat invert_exec.            
             {
               right; right; right; right; unfold cached_log_rep; simpl.
               intuition eauto.
               rewrite <- sync_shift_comm.
               rewrite shift_upd_set_noop.
               rewrite total_mem_map_fst_sync_noop; eauto.
               {
                 intros; pose proof hdr_before_log.
                 pose proof data_start_where_log_ends.
                 lia.
               }
             }
          }
          repeat invert_exec.
          split_ors; cleanup; repeat invert_exec.
          { (** Second commit crashed **)
            simpl in *.
            destruct (addr_list_to_blocks_to_addr_list (map (Init.Nat.add data_start) al)).
            eapply commit_crashed in H5; eauto.
            split_ors; cleanup; 
            simpl in *; repeat cleanup_pairs.
            {
              left.
              eexists; intuition eauto.
              simpl; eauto.
              simpl.
              rewrite <- sync_shift_comm.
              rewrite shift_upd_set_noop.
              rewrite total_mem_map_fst_sync_noop; eauto.
              {
                intros; pose proof hdr_before_log.
                pose proof data_start_where_log_ends.
                lia.
              }
            }
            split_ors; cleanup; 
            simpl in *; repeat cleanup_pairs.
            {
              right; left; left; eexists; intuition eauto.
              simpl.
              rewrite <- sync_shift_comm; simpl.
              rewrite shift_eq_after with (m1:= s2) (m2:= sync
         (upd_set (list_upd_batch_set s1 (map addr_list x) (map data_blocks x)) hdr_block_num
                  (encode_header (update_hdr x0 header_part0)))).
              rewrite <- sync_shift_comm.
              rewrite shift_upd_set_noop.
              repeat rewrite total_mem_map_fst_sync_noop; eauto.
              {
                intros; pose proof hdr_before_log.
                pose proof data_start_where_log_ends.
                lia.
              }
              intros; lia.
              intros; apply H2; lia.
            }
            split_ors; cleanup; 
            simpl in *; repeat cleanup_pairs.
            {
              right; left; right; do 2 eexists; intuition eauto.
              simpl.
              replace (addr_list x1) with (map (Init.Nat.add data_start) al).
              rewrite <- shift_upd_batch_comm.
              rewrite <- sync_shift_comm; simpl.
              rewrite shift_eq_after with (m1:= s2) (m2:= sync
         (upd_set (list_upd_batch_set s1 (map addr_list x) (map data_blocks x)) hdr_block_num
            (encode_header (update_hdr x0 header_part0)))).
              rewrite <- sync_shift_comm.
              rewrite shift_upd_set_noop.
              rewrite <- total_mem_map_fst_upd_batch_set.
              rewrite sync_idempotent.
              repeat rewrite <- sync_upd_batch_set_comm.
              repeat rewrite total_mem_map_fst_sync_noop; eauto.              
              {
                intros; pose proof hdr_before_log.
                pose proof data_start_where_log_ends.
                lia.
              }
              intros; lia.
              intros; apply H7; lia.
              {
                unfold sumbool_agree; intros; intuition eauto.
                destruct (addr_dec x3 y); subst.
                destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
                destruct (addr_dec (data_start + x3) (data_start + y)); eauto; lia.
              }
              {
                unfold log_crash_rep in *; cleanup.
                simpl in *.
                unfold log_rep_inner, txns_valid in H15; cleanup.
                inversion H18; cleanup.
                unfold txn_well_formed in H21; simpl in *; cleanup.
                rewrite firstn_app2; eauto.
                rewrite map_length; eauto.
              }
              {
                simpl.
                rewrite <- sync_shift_comm; simpl.
                rewrite shift_eq_after with (m1:= s2) (m2:= sync
         (upd_set (list_upd_batch_set s1 (map addr_list x) (map data_blocks x)) hdr_block_num
            (encode_header (update_hdr x0 header_part0)))).
                rewrite <- sync_shift_comm.
                rewrite shift_upd_set_noop.
                repeat rewrite total_mem_map_fst_sync_noop; eauto.
                {
                  intros; pose proof hdr_before_log.
                  pose proof data_start_where_log_ends.
                  lia.
                }
                intros; lia.
                intros; apply H7; lia.
              }
             }
            {
              right; right; left; eexists; intuition eauto.
              simpl.
              replace (addr_list x1) with (map (Init.Nat.add data_start) al).
              rewrite <- shift_upd_batch_comm.
              rewrite <- sync_shift_comm; simpl.
              rewrite shift_eq_after with (m1:= s2) (m2:= sync
         (sync
            (upd_set (list_upd_batch_set s1 (map addr_list x) (map data_blocks x)) hdr_block_num
                     (encode_header (update_hdr x0 header_part0))))).
              rewrite sync_idempotent.
              rewrite <- sync_shift_comm.
              rewrite shift_upd_set_noop.
              rewrite <- total_mem_map_fst_upd_batch_set.
              rewrite sync_idempotent.
              repeat rewrite <- sync_upd_batch_set_comm.
              repeat rewrite total_mem_map_fst_sync_noop; eauto.              
              
              {
                intros; pose proof hdr_before_log.
                pose proof data_start_where_log_ends.
                lia.
              }
              intros; lia.
              intros; apply H7; lia.
              {
                unfold sumbool_agree; intros; intuition eauto.
                destruct (addr_dec x3 y); subst.
                destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
                destruct (addr_dec (data_start + x3) (data_start + y)); eauto; lia.
              }
              {
                unfold log_rep, log_rep_general, log_rep_explicit in *; cleanup.
                simpl in *.
                unfold log_rep_inner, txns_valid in H12; cleanup.
                inversion H3; cleanup.
                unfold txn_well_formed in H26; simpl in *; cleanup.
                rewrite firstn_app2; eauto.
                rewrite map_length; eauto.
              }
            }
            all: try rewrite H6, firstn_app2.
            all: try rewrite app_length;
            try rewrite map_length; try lia.
            {
              apply FinFun.Injective_map_NoDup; eauto.
              unfold FinFun.Injective; intros; lia.
            }
            {
              apply Forall_forall; intros.
              apply in_map_iff in H7; cleanup_no_match.
              eapply_fresh Forall_forall in f; eauto.
              pose proof data_fits_in_disk.
              split; try lia.
            }
            {
              rewrite H6, app_length, map_length; lia.
            }
          }
          unfold log_rep in *; logic_clean.
          destruct (addr_list_to_blocks_to_addr_list (map (Init.Nat.add data_start) al)).
          eapply commit_finished in H5; eauto.
          simpl in *; repeat cleanup_pairs; simpl in *.
          split_ors; cleanup; try congruence; try lia.
          2: {
            unfold log_rep_general, log_rep_explicit, log_header_block_rep in *; simpl in *; logic_clean.
            unfold sync, upd_set in H2.
            destruct (addr_dec hdr_block_num hdr_block_num); try lia.
            destruct (list_upd_batch_set s1 (map addr_list x) (map data_blocks x) hdr_block_num); simpl in *;
            destruct x1; simpl in *; cleanup;
            rewrite encode_decode_header, app_length in H5; simpl in *;
            lia.
          }
          {
            right; right; left; unfold cached_log_crash_rep; simpl.
            eexists; intuition eauto.
            simpl.
            replace (addr_list x1) with (map (Init.Nat.add data_start) al).
            rewrite <- shift_upd_batch_comm.
            rewrite <- sync_shift_comm; simpl.
            rewrite shift_eq_after with (m1:= s2) (m2:= sync
         (sync
            (upd_set (list_upd_batch_set s1 (map addr_list x) (map data_blocks x)) hdr_block_num
                     (encode_header (update_hdr x0 header_part0))))).
              rewrite sync_idempotent.
              rewrite <- sync_shift_comm.
              rewrite shift_upd_set_noop.
              rewrite <- total_mem_map_fst_upd_batch_set.
              rewrite sync_idempotent.
              repeat rewrite <- sync_upd_batch_set_comm.
              repeat rewrite total_mem_map_fst_sync_noop; eauto.              
              
              {
                intros; pose proof hdr_before_log.
                pose proof data_start_where_log_ends.
                lia.
              }
              intros; lia.
              intros; apply H8; lia.
              {
                unfold sumbool_agree; intros; intuition eauto.
                destruct (addr_dec x2 y); subst.
                destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
                destruct (addr_dec (data_start + x2) (data_start + y)); eauto; lia.
              }
              {
                unfold log_rep, log_rep_general, log_rep_explicit in *; cleanup.
                simpl in *.
                unfold log_rep_inner, txns_valid in H12; cleanup.
                inversion H3; cleanup.
                unfold txn_well_formed in H26; simpl in *; cleanup.
                rewrite firstn_app2; eauto.
                rewrite map_length; eauto.
              }
            }
            all: try rewrite H6, firstn_app2.
            all: try rewrite app_length;
            try rewrite map_length; try lia.
            {
              apply FinFun.Injective_map_NoDup; eauto.
              unfold FinFun.Injective; intros; lia.
            }
            {
              apply Forall_forall; intros.
              apply in_map_iff in H7; cleanup_no_match.
              eapply_fresh Forall_forall in f; eauto.
              pose proof data_fits_in_disk.
              split; try lia.
            }
            {
              rewrite H6, app_length, map_length; lia.
            }
        }
        {(** write_batch_to_cache_crashed **)
          eapply apply_log_finished in H5; eauto.
          simpl in *; cleanup.
          unfold log_rep in *; logic_clean.
          destruct (addr_list_to_blocks_to_addr_list (map (Init.Nat.add data_start) al)).
          simpl in *; repeat cleanup_pairs; simpl in *.
          eapply commit_finished in H6; eauto.
          simpl in *; repeat cleanup_pairs; simpl in *.
          split_ors; cleanup; try congruence; try lia.
          2: {
            unfold log_rep_general, log_rep_explicit, log_header_block_rep in *; simpl in *; logic_clean.
            unfold sync, upd_set in H2.
            destruct (addr_dec hdr_block_num hdr_block_num); try lia.
            destruct (list_upd_batch_set s1 (map addr_list x) (map data_blocks x) hdr_block_num); simpl in *;
            destruct x1; simpl in *; cleanup;
            rewrite encode_decode_header, app_length in H5; simpl in *;
            lia.
          }
          eapply write_batch_to_cache_crashed in H1; eauto.
          simpl in *; cleanup.
          repeat cleanup_pairs; simpl in *.
          {
            right; right; left; unfold cached_log_crash_rep; simpl.
            eexists; intuition eauto.
            simpl.
            replace (addr_list x1) with (map (Init.Nat.add data_start) al).
            rewrite <- shift_upd_batch_comm.
            rewrite <- sync_shift_comm; simpl.
            rewrite shift_eq_after with (m1:= s2) (m2:= sync
         (sync
            (upd_set (list_upd_batch_set s1 (map addr_list x) (map data_blocks x)) hdr_block_num
                     (encode_header (update_hdr x0 header_part0))))).
              rewrite sync_idempotent.
              rewrite <- sync_shift_comm.
              rewrite shift_upd_set_noop.
              rewrite <- total_mem_map_fst_upd_batch_set.
              rewrite sync_idempotent.
              repeat rewrite <- sync_upd_batch_set_comm.
              repeat rewrite total_mem_map_fst_sync_noop; eauto.              
              
              {
                intros; pose proof hdr_before_log.
                pose proof data_start_where_log_ends.
                lia.
              }
              intros; lia.
              intros; apply H9; lia.
              {
                unfold sumbool_agree; intros; intuition eauto.
                destruct (addr_dec x5 y); subst.
                destruct (addr_dec (data_start + y) (data_start + y)); eauto; congruence.
                destruct (addr_dec (data_start + x5) (data_start + y)); eauto; lia.
              }
              {
                unfold log_rep, log_rep_general, log_rep_explicit in *; cleanup.
                simpl in *.
                unfold log_rep_inner, txns_valid in H12; cleanup.
                inversion H1; cleanup.
                unfold txn_well_formed in H26; simpl in *; cleanup.
                rewrite firstn_app2; eauto.
                rewrite map_length; eauto.
              }
            }
            all: try rewrite H8, firstn_app2.
            all: try rewrite app_length;
            try rewrite map_length; try lia.
            {
              apply FinFun.Injective_map_NoDup; eauto.
              unfold FinFun.Injective; intros; lia.
            }
            {
              apply Forall_forall; intros.
              apply in_map_iff in H2; cleanup_no_match.
              eapply_fresh Forall_forall in f; eauto.
              pose proof data_fits_in_disk.
              split; try lia.
            }
            {
              rewrite H8, app_length, map_length; lia.
            }
        }
      }
      all: destruct (addr_list_to_blocks_to_addr_list (map (Init.Nat.add data_start) al)).
      all: try rewrite H1, firstn_app2.
      all: try rewrite app_length;
      try rewrite map_length; try lia.
      {
        apply FinFun.Injective_map_NoDup; eauto.
        unfold FinFun.Injective; intros; lia.
      }
      {
        apply Forall_forall; intros.
        apply in_map_iff in H2; cleanup_no_match.
        eapply_fresh Forall_forall in f; eauto.
        pose proof data_fits_in_disk.
        split; try lia.
      }
      {
        rewrite H1, app_length, map_length; lia.
      }
    }
  }
  all: try solve [left; eexists; intuition eauto].
  Unshelve.
  apply value0.
Qed.


  
  
