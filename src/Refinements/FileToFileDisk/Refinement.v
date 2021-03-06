Require Import Framework FSParameters.
Require Import AuthenticatedDiskLayer FileDiskLayer.
Require Import File FileToFileDisk.Definitions.
Require Import ClassicalFacts FunctionalExtensionality Lia.

Set Nested Proofs Allowed.

Local Notation "'imp'" := AuthenticatedDiskLang.
Local Notation "'abs'" := (FileDiskLang inode_count).
Local Notation "'refinement'" := FileDiskRefinement.

Section FileDiskSimulation.

  Definition authenticated_disk_reboot_list n :=
    repeat (fun s: imp.(state) => (fst s, (snd (snd s), snd (snd s)))) n.

  Definition file_disk_reboot_list n :=
    repeat (fun s : abs.(state) => s) n.

  Ltac unify_execs :=
    match goal with
    |[H : recovery_exec ?u ?x ?y ?z ?a ?b ?c _,
      H0 : recovery_exec ?u ?x ?y ?z ?a ?b ?c _ |- _ ] =>
     eapply recovery_exec_deterministic_wrt_reboot_state in H; [| apply H0]
    | [ H: exec ?u ?x ?y ?z ?a _,
        H0: exec ?u ?x ?y ?z ?a _ |- _ ] =>
      eapply exec_deterministic_wrt_oracle in H; [| apply H0]
    | [ H: exec' ?u ?x ?y ?z _,
        H0: exec' ?u ?x ?y ?z _ |- _ ] =>
      eapply exec_deterministic_wrt_oracle in H; [| apply H0]
    | [ H: exec _ ?u ?x ?y ?z _,
        H0: Language.exec' ?u ?x ?y ?z _ |- _ ] =>
      eapply exec_deterministic_wrt_oracle in H; [| apply H0]
    end.
  
  Lemma recovery_oracles_refine_to_length:
    forall O_imp O_abs (L_imp: Language O_imp) (L_abs: Language O_abs) (ref: Refinement L_imp L_abs)
      l_o_imp l_o_abs T (u: user) s (p1: L_abs.(prog) T) rec l_rf u, 
      recovery_oracles_refine_to ref u s p1 rec l_rf l_o_imp l_o_abs ->
      length l_o_imp = length l_o_abs.
  Proof.
    induction l_o_imp; simpl; intros; eauto.
    tauto.
    destruct l_o_abs; try tauto; eauto.
  Qed.

  Lemma app_ne_diag:
    forall A (l l1: list A),
      l1 <> [] ->
      l ++ l1 <> l.
  Proof.
    induction l; simpl in *; intros; eauto.
    intros Hx.
    eapply IHl; eauto.
    congruence.
  Qed.
  
  (*** Abstract Oracles ***)
  
  Theorem abstract_oracles_exist_wrt_recover:
    forall n u, 
      abstract_oracles_exist_wrt refinement refines_to_reboot u (|Recover|) (|Recover|) (authenticated_disk_reboot_list n).
  Proof.
    unfold abstract_oracles_exist_wrt, refines_to_reboot; induction n;
    simpl; intros; cleanup; invert_exec.
    {
      exists  [ [OpToken (FileDiskOperation inode_count) Cont] ]; simpl.
      intuition eauto.
      eexists; intuition eauto.
      left.
      eexists; intuition eauto.
      destruct t0; eauto.
      eapply_fresh recover_finished in H0; eauto.
      unify_execs; cleanup.
    }
    { 
      eapply IHn in H11; eauto; cleanup.
      exists ([OpToken (FileDiskOperation inode_count) CrashBefore]::x0); simpl.
      eapply_fresh recover_crashed in H10; eauto; cleanup.
      repeat split; eauto; try (unify_execs; cleanup).
      eapply recovery_oracles_refine_to_length in H0; eauto.
      intros; unify_execs; cleanup.
      eexists; repeat split; eauto;
      simpl in *.
      intros.

      eapply_fresh recover_crashed in H10; eauto; cleanup.
      eauto.
      eapply_fresh recover_crashed in H10; eauto; cleanup.      
    }
  Qed.

  Theorem abstract_oracles_exist_wrt_recover':
    forall n u, 
      abstract_oracles_exist_wrt refinement refines_to u (|Recover|) (|Recover|) (authenticated_disk_reboot_list n).
  Proof.
    unfold abstract_oracles_exist_wrt, refines_to_reboot; destruct n;
    simpl; intros; cleanup; invert_exec.
    {
      exists  [ [OpToken (FileDiskOperation inode_count) Cont] ]; simpl.
      intuition eauto.
      eexists; intuition eauto.
      
      unify_execs; cleanup.
      eapply_fresh recover_finished in H7; eauto.
      left; eexists; intuition eauto.
      destruct t0; eauto.
      unify_execs; cleanup.      
    }
    {        
      eapply abstract_oracles_exist_wrt_recover in H11; eauto; cleanup.
      exists ([OpToken (FileDiskOperation inode_count) CrashBefore]::x0); simpl.
      eapply_fresh recover_crashed in H10; eauto; cleanup.
      repeat split; eauto; try (unify_execs; cleanup).
      eapply recovery_oracles_refine_to_length in H0; eauto.
      intros; unify_execs; cleanup.
      eexists; repeat split; eauto;
      simpl in *.
      intros.
      
      eapply_fresh recover_crashed in H10; eauto; cleanup.
      eauto.
      unfold refines_to, files_rep, files_reboot_rep, files_crash_rep in *;
      simpl; cleanup; eauto.
      
      eapply_fresh recover_crashed in H10; eauto; cleanup.
      unfold refines_to, refines_to_reboot,
      files_rep, files_reboot_rep, files_crash_rep in *;
      simpl; cleanup; eauto.
    }
  Qed.

  Theorem abstract_oracles_exist_wrt_read:
    forall n a inum u, 
      abstract_oracles_exist_wrt refinement refines_to u (|Read inum a|) (|Recover|) (authenticated_disk_reboot_list n).
  Proof.
    unfold abstract_oracles_exist_wrt, refines_to,
    refines_to_reboot; destruct n;
    simpl; intros; cleanup; invert_exec.
    {
      exists  [ [OpToken (FileDiskOperation inode_count) Cont] ]; simpl.
      intuition eauto.
      eexists; intuition eauto.
      left; eexists; intuition eauto.
      unify_execs; cleanup.
      eapply_fresh read_finished in H7; eauto.
      eexists; intuition eauto.
      unify_execs; cleanup.      
    }
    {        
      eapply abstract_oracles_exist_wrt_recover in H11; eauto; cleanup.
      exists ([OpToken (FileDiskOperation inode_count) CrashBefore]::x0); simpl.
      eapply_fresh read_crashed in H10; eauto; cleanup.
      repeat split; eauto; try (unify_execs; cleanup).
      eapply recovery_oracles_refine_to_length in H0; eauto.
      intros; unify_execs; cleanup.
      eexists; repeat split; eauto;
      simpl in *; intros.      

      eapply_fresh read_crashed in H10; eauto; cleanup.
      eauto.
      eapply_fresh read_crashed in H10; eauto; cleanup.      
    }
  Qed.
  
  Theorem abstract_oracles_exist_wrt_write:
    forall n inum a v u,
      abstract_oracles_exist_wrt refinement refines_to u (|Write inum a v|) (|Recover|) (authenticated_disk_reboot_list n).
  Proof.
    unfold abstract_oracles_exist_wrt, refines_to,
    refines_to_reboot; destruct n;
    simpl; intros; cleanup; invert_exec.
    {      
      {
        exists  [ [OpToken (FileDiskOperation inode_count) Cont] ]; simpl.
        split; eauto.
        intros.
        eexists; repeat split; eauto.
        intros.
        eexists; repeat split; eauto.
        intros.
        eapply_fresh write_finished in H7; eauto.
        split_ors; cleanup;        
        left; eexists; repeat (split; eauto);
        unify_execs; cleanup;

        repeat split_ors; cleanup;
        do 2 eexists;
        try solve [right; eauto;
                   repeat (split; eauto) ].
        left; repeat (split; eauto).
        intros; unify_execs; cleanup.
      }
    }
    {        
      eapply abstract_oracles_exist_wrt_recover in H11; eauto; cleanup.
      eapply_fresh write_crashed in H10; eauto; cleanup.
      split_ors; cleanup.
      {
        exists ([OpToken (FileDiskOperation inode_count) CrashBefore]::x0); simpl.
        repeat split; eauto; try (unify_execs; cleanup).
        eapply recovery_oracles_refine_to_length in H0; eauto.
        intros; unify_execs; cleanup.
        eexists; repeat split; eauto;
        simpl in *; intros.
        eapply files_rep_eq in H; eauto; subst.
        right; eexists; intuition eauto.
        eauto.
      }
      {
        exists ([OpToken (FileDiskOperation inode_count) CrashAfter]::x0); simpl.
        repeat split; eauto; try (unify_execs; cleanup).
        eapply recovery_oracles_refine_to_length in H0; eauto.
        apply (owner x1).
    
        intros; unify_execs; cleanup.
        eexists; repeat split; eauto;
        simpl in *; intros.
        eapply files_rep_eq in H; eauto; subst.
        
        right; eexists; intuition eauto.
        right; eexists; repeat (split; eauto).
        eauto.
      }
          
      eapply_fresh write_crashed in H10; eauto; cleanup.
      split_ors; cleanup;
      unfold refines_to, refines_to_reboot,
      files_rep, files_reboot_rep, files_crash_rep in *;
      simpl; cleanup; eauto.
    }
    
    Unshelve.
    all: repeat constructor; eauto.
  Qed.

    Theorem abstract_oracles_exist_wrt_extend:
    forall n inum v u, 
      abstract_oracles_exist_wrt refinement refines_to u (|Extend inum v|) (|Recover|) (authenticated_disk_reboot_list n).
  Proof.
    unfold abstract_oracles_exist_wrt,
    refines_to, refines_to_reboot; destruct n;
    simpl; intros; cleanup; invert_exec.
    {      
      eapply_fresh extend_finished in H7; eauto.
      split_ors; cleanup.
      {
        exists  [ [OpToken (FileDiskOperation inode_count) Cont] ]; simpl.
        split; eauto.
        intros.
        eexists; repeat split; eauto.
        intros.
        eexists; repeat (split; eauto).
        intros; eapply files_rep_eq in H; eauto; subst.
        left; eexists; repeat (split; eauto).
        unify_execs; cleanup.

        repeat split_ors; cleanup;
        do 2 eexists; right; eauto;
        left; repeat (split; eauto).        
        intros; unify_execs; cleanup.
      }
      {
        exists  [ [OpToken (FileDiskOperation inode_count) Cont] ]; simpl.
        intuition eauto.
        eexists; intuition eauto.
        left; eexists; intuition eauto.
        unify_execs; cleanup.
        eapply files_rep_eq in H; eauto; subst.
        do 2 eexists; left; repeat (split; eauto).
        unify_execs; cleanup.
      }
    }
    {        
      eapply abstract_oracles_exist_wrt_recover in H11; eauto; cleanup.
      eapply_fresh extend_crashed in H10; eauto; cleanup.
      split_ors; cleanup.
      {
        exists ([OpToken (FileDiskOperation inode_count) CrashBefore]::x0); simpl.
        repeat split; eauto; try (unify_execs; cleanup).
        eapply recovery_oracles_refine_to_length in H0; eauto.
        intros; unify_execs; cleanup.
        eexists; repeat split; eauto;
        simpl in *; intros;
        eapply files_rep_eq in H; eauto; subst.
        
        right; eexists; intuition eauto.
        eauto.
      }
      {
        exists ([OpToken (FileDiskOperation inode_count) CrashAfter]::x0); simpl.
        repeat split; eauto; try (unify_execs; cleanup).
        eapply recovery_oracles_refine_to_length in H0; eauto.
        apply (owner x1).
    
        intros; unify_execs; cleanup.
        eexists; repeat split; eauto;
        simpl in *; intros;
        eapply files_rep_eq in H; eauto; subst.
        
        right; eexists; intuition eauto.
        right; eexists; repeat (split; eauto).
        eauto.
      }
          
      {
        eapply_fresh extend_crashed in H10; eauto; cleanup.
        split_ors; cleanup;
        unfold refines_to, refines_to_reboot,
        files_rep, files_reboot_rep, files_crash_rep in *;
        simpl; cleanup; eauto.
      }
    }
    
    Unshelve.
    all: repeat econstructor; eauto.
  Qed.

  Theorem abstract_oracles_exist_wrt_delete:
    forall n inum u, 
      abstract_oracles_exist_wrt refinement refines_to u (|Delete inum|) (|Recover|) (authenticated_disk_reboot_list n).
  Proof.
    Proof.
    unfold abstract_oracles_exist_wrt,
    refines_to, refines_to_reboot; destruct n;
    simpl; intros; cleanup; invert_exec.
    {      
      eapply_fresh delete_finished in H7; eauto.
      split_ors; cleanup.
      {
        exists  [ [OpToken (FileDiskOperation inode_count) Cont] ]; simpl.
        split; eauto.
        intros.
        eexists; repeat split; eauto.
        intros.
        eexists; repeat split; eauto.
        intros;
        eapply files_rep_eq in H; eauto; subst.
        left; eexists; repeat (split; eauto).
        unify_execs; cleanup.

        repeat split_ors; cleanup;
        do 2 eexists; right; eauto;
        repeat (split; eauto).        
        intros; unify_execs; cleanup.
      }
      {
        exists  [ [OpToken (FileDiskOperation inode_count) Cont] ]; simpl.
        intuition eauto.
        eexists; intuition eauto.
        eapply files_rep_eq in H; eauto; subst.
        left; eexists; intuition eauto.
        unify_execs; cleanup.
        do 2 eexists; left; repeat (split; eauto).
        unify_execs; cleanup.
      }
    }
    {        
      eapply abstract_oracles_exist_wrt_recover in H11; eauto; cleanup.
      eapply_fresh delete_crashed in H10; eauto; cleanup.
      split_ors; cleanup.
      {
        exists ([OpToken (FileDiskOperation inode_count) CrashBefore]::x0); simpl.
        repeat split; eauto; try (unify_execs; cleanup).
        eapply recovery_oracles_refine_to_length in H0; eauto.
        intros; unify_execs; cleanup.
        eexists; repeat split; eauto;
        simpl in *; intros;
        eapply files_rep_eq in H; eauto; subst.
        
        right; eexists; intuition eauto.
        eauto.
      }
      {
        exists ([OpToken (FileDiskOperation inode_count) CrashAfter]::x0); simpl.
        repeat split; eauto; try (unify_execs; cleanup).
        eapply recovery_oracles_refine_to_length in H0; eauto.
        apply (owner x1).
    
        intros; unify_execs; cleanup.
        eexists; repeat split; eauto;
        simpl in *; intros;
        eapply files_rep_eq in H; eauto; subst.
        
        right; eexists; intuition eauto.
        right; eexists; repeat (split; eauto).
        eauto.
      }
          
      {
        eapply_fresh delete_crashed in H10; eauto; cleanup.
        split_ors; cleanup;
        unfold refines_to, refines_to_reboot,
        files_rep, files_reboot_rep, files_crash_rep in *;
        simpl; cleanup; eauto.
      }
    }
    
    Unshelve.
    all: repeat econstructor; eauto.
    Qed.

    Theorem abstract_oracles_exist_wrt_change_owner:
    forall n inum own u, 
      abstract_oracles_exist_wrt refinement refines_to u (|ChangeOwner inum own|) (|Recover|) (authenticated_disk_reboot_list n).
  Proof.
    Proof.
    unfold abstract_oracles_exist_wrt,
    refines_to, refines_to_reboot; destruct n;
    simpl; intros; cleanup; invert_exec.
    {      
      eapply_fresh change_owner_finished in H7; eauto.
      split_ors; cleanup.
      {
        exists  [ [OpToken (FileDiskOperation inode_count) Cont] ]; simpl.
        split; eauto.
        intros.
        eexists; repeat split; eauto.
        intros.
        eexists; repeat split; eauto.
        intros;
        eapply files_rep_eq in H; eauto; subst.
        left; eexists; repeat (split; eauto).
        unify_execs; cleanup.

        repeat split_ors; cleanup;
        do 2 eexists; right; eauto;
        repeat (split; eauto).        
        intros; unify_execs; cleanup.
      }
      {
        exists  [ [OpToken (FileDiskOperation inode_count) Cont] ]; simpl.
        intuition eauto.
        eexists; intuition eauto.
        eapply files_rep_eq in H; eauto; subst.
        left; eexists; intuition eauto.
        unify_execs; cleanup.
        do 2 eexists; left; repeat (split; eauto).
        unify_execs; cleanup.
      }
    }
    {        
      eapply abstract_oracles_exist_wrt_recover in H11; eauto; cleanup.
      eapply_fresh change_owner_crashed in H10; eauto; cleanup.
      split_ors; cleanup.
      {
        exists ([OpToken (FileDiskOperation inode_count) CrashBefore]::x0); simpl.
        repeat split; eauto; try (unify_execs; cleanup).
        eapply recovery_oracles_refine_to_length in H0; eauto.
        intros; unify_execs; cleanup.
        eexists; repeat split; eauto;
        simpl in *; intros;
        eapply files_rep_eq in H; eauto; subst.
        
        right; eexists; intuition eauto.
        eauto.
      }
      {
        exists ([OpToken (FileDiskOperation inode_count) CrashAfter]::x0); simpl.
        repeat split; eauto; try (unify_execs; cleanup).
        eapply recovery_oracles_refine_to_length in H0; eauto.
    
        intros; unify_execs; cleanup.
        eexists; repeat split; eauto;
        simpl in *; intros;
        eapply files_rep_eq in H; eauto; subst.
        
        right; eexists; intuition eauto.
        right; eexists; repeat (split; eauto).
        eauto.
      }          
      {
        eapply_fresh change_owner_crashed in H10; eauto; cleanup.
        split_ors; cleanup;
        unfold refines_to, refines_to_reboot,
        files_rep, files_reboot_rep, files_crash_rep in *;
        simpl; cleanup; eauto.
      }
    }
    
    Unshelve.
    all: repeat econstructor; eauto.
    Qed.

    Theorem abstract_oracles_exist_wrt_create:
    forall n own u, 
      abstract_oracles_exist_wrt refinement refines_to u (|Create own|) (|Recover|) (authenticated_disk_reboot_list n).
  Proof.
    Proof.
    unfold addr, abstract_oracles_exist_wrt,
    refines_to, refines_to_reboot; destruct n;
    simpl; intros; cleanup; invert_exec.
    {      
      eapply_fresh create_finished in H7; eauto.
      split_ors; cleanup.
      {
        exists  [ [OpToken (FileDiskOperation inode_count) InodesFull] ]; simpl.
        split; eauto.
        intros.
        eexists; repeat split; eauto.
        intros.
        eexists; repeat split; eauto.
        intros;
        eapply files_rep_eq in H; eauto; subst.
        left; eexists; repeat (split; eauto).
        unify_execs; cleanup.

        right.        
        repeat split_ors; cleanup;
        eexists; eauto;
        repeat (split; eauto).
        intros; unify_execs; cleanup.
      }
      {
        exists  [ [OpToken (FileDiskOperation inode_count) (NewInum x0)] ]; simpl.
        intuition eauto.
        eexists; intuition eauto.
        eapply files_rep_eq in H; eauto; subst.
        left; eexists; intuition eauto.
        unify_execs; cleanup.
        left; eexists; repeat (split; eauto).
        unify_execs; cleanup.
      }
    }
    {        
      eapply abstract_oracles_exist_wrt_recover in H11; eauto; cleanup.
      eapply_fresh create_crashed in H10; eauto; cleanup.
      split_ors; cleanup.
      {
        exists ([OpToken (FileDiskOperation inode_count) CrashBefore]::x0); simpl.
        repeat split; eauto; try (unify_execs; cleanup).
        eapply recovery_oracles_refine_to_length in H0; eauto.
        intros; unify_execs; cleanup.
        eexists; repeat split; eauto;
        simpl in *; intros;
        eapply files_rep_eq in H; eauto; subst.
        right; eexists; intuition eauto.
        eauto.
      }
      {
        exists ([OpToken (FileDiskOperation inode_count) (CrashAfterCreate x1)]::x0); simpl.
        repeat split; eauto; try (unify_execs; cleanup).
        eapply recovery_oracles_refine_to_length in H0; eauto.
    
        intros; unify_execs; cleanup.
        eexists; repeat split; eauto;
        simpl in *;intros;
        eapply files_rep_eq in H; eauto; subst.
        
        right; eexists; intuition eauto.
        right; eexists; repeat (split; eauto).
        eauto.
      }          
      {
        eapply_fresh create_crashed in H10; eauto; cleanup.
        split_ors; cleanup;
        unfold refines_to, refines_to_reboot,
        files_rep, files_reboot_rep, files_crash_rep in *;
        simpl; cleanup; eauto.
      }
    }
    Qed.
    
    
  Theorem abstract_oracles_exists_file_disk:
    forall T (p_abs: abs.(prog) T) n u, 
      abstract_oracles_exist_wrt refinement refines_to u p_abs (|Recover|) (authenticated_disk_reboot_list n).
  Proof.
    unfold abstract_oracles_exist_wrt; induction p_abs;
    simpl; intros; cleanup.
    {(** OPS **)
      destruct o.
      eapply abstract_oracles_exist_wrt_read; eauto.
      eapply abstract_oracles_exist_wrt_write; eauto.
      eapply abstract_oracles_exist_wrt_extend; eauto.
      eapply abstract_oracles_exist_wrt_change_owner; eauto.
      eapply abstract_oracles_exist_wrt_create; eauto.
      eapply abstract_oracles_exist_wrt_delete; eauto.
      eapply abstract_oracles_exist_wrt_recover'; eauto.
    }
    {
      repeat invert_exec; cleanup.
      {
        rewrite <- H1; simpl.
        exists [[Language.Cont (FileDiskOperation inode_count) ]]; simpl; intuition.
        right; intuition eauto.
        unify_execs; cleanup.
      }
      {
        destruct n; unfold authenticated_disk_reboot_list in *;
        simpl in *; try congruence; cleanup.
        repeat invert_exec.
        invert_exec'' H8.
        simpl in *.
        eapply abstract_oracles_exist_wrt_recover in H10; eauto.
        cleanup.
        exists ([Language.Crash (FileDiskOperation inode_count)]::x0);
        simpl; intuition eauto.
        apply recovery_oracles_refine_to_length in H0; eauto.
        left; eexists; intuition eauto.
        econstructor.
        invert_exec'' H1; eauto.
        unfold refines_to, refines_to_reboot,
        files_rep, files_reboot_rep, files_crash_rep in *.
        cleanup; eauto.
      }
    }
    {
      repeat invert_exec.
      {
        invert_exec'' H10.
        edestruct IHp_abs; eauto.
        instantiate (2:= 0); simpl.
        eapply ExecFinished; eauto.
        edestruct H.
        2: {
          instantiate (3:= 0); simpl.
          eapply ExecFinished; eauto.
        }
        eapply exec_compiled_preserves_refinement_finished in H8; eauto.
        simpl in *; cleanup; try tauto.
        simpl in *.
        exists ([o0 ++ o]); intuition eauto.
        do 4 eexists; intuition eauto.
        right; simpl; repeat eexists; intuition eauto.
        invert_exec; split_ors; cleanup; repeat (unify_execs; cleanup).        
        eapply finished_not_crashed_oracle_prefix in H8; eauto.
        eapply exec_finished_deterministic_prefix in H8; eauto; cleanup.
        unify_execs; cleanup.
      }
      {
        destruct n; unfold authenticated_disk_reboot_list in *;
        simpl in *; try congruence; cleanup.
        invert_exec'' H9.
        {
          edestruct IHp_abs; eauto.
          instantiate (2:= 0); simpl.
          instantiate (1:= RFinished d1' r).
          eapply ExecFinished; eauto.
          edestruct H.
          2: {
            instantiate (3:= S n); simpl.
            instantiate (1:= Recovered (extract_state_r ret)).
            econstructor; eauto.
          }
          eapply exec_compiled_preserves_refinement_finished in H7; eauto.
          simpl in *; cleanup; try tauto.
          simpl in *.
          exists ((o0 ++ o)::l); intuition eauto.
          - invert_exec; try split_ors; repeat (unify_execs; cleanup).
            eapply exec_finished_deterministic_prefix in H7; eauto; cleanup.
            unify_execs; cleanup.
          - invert_exec; cleanup; try split_ors; try cleanup;
            repeat (unify_execs; cleanup).
            exfalso; eapply finished_not_crashed_oracle_prefix in H7; eauto.
            eapply exec_finished_deterministic_prefix in H7; eauto; cleanup.
            unify_execs; cleanup; eauto.
            specialize H4 with (1:= H12); cleanup.
            do 4 eexists; intuition eauto.
            right; simpl; repeat eexists; intuition eauto.
          - invert_exec; cleanup; try split_ors; try cleanup;
            repeat (unify_execs; cleanup).
            exfalso; eapply finished_not_crashed_oracle_prefix in H7; eauto.
            eapply exec_finished_deterministic_prefix in H7; eauto; cleanup.
            unify_execs; cleanup; eauto.
            specialize H4 with (1:= H12); cleanup; eauto.
        }
        {
          edestruct IHp_abs; eauto.
          instantiate (2:= S n); simpl.
          instantiate (1:= Recovered (extract_state_r ret)).
          econstructor; eauto.
          simpl in *; cleanup; try tauto.
          simpl in *.
          exists (o::l); intuition eauto.
          - invert_exec; cleanup; try split_ors;
            cleanup; repeat (unify_execs; cleanup).            
            exfalso; eapply finished_not_crashed_oracle_prefix in H4; eauto.
          - invert_exec; cleanup; try split_ors;
            cleanup; repeat (unify_execs; cleanup).
            eapply_fresh exec_deterministic_wrt_oracle_prefix in H6; eauto; cleanup.
            specialize H3 with (1:= H6).
            clear H5.
            logic_clean; eauto.
            exists o1, o2, o, nil; intuition eauto.
            rewrite app_nil_r; eauto.
            eapply_fresh exec_deterministic_wrt_oracle_prefix in H6;
            eauto; cleanup.
          - invert_exec; cleanup; try split_ors;
            cleanup; repeat (unify_execs; cleanup).
            eapply_fresh exec_deterministic_wrt_oracle_prefix in H6; eauto; cleanup.
            specialize H3 with (1:= H6).
            clear H5.
            logic_clean; eauto.
            eapply_fresh exec_deterministic_wrt_oracle_prefix in H6;
            eauto; cleanup.
        }
      }
    }
  Qed.

  Lemma addrs_match_upd:
    forall A AEQ V1 V2 (m1: @mem A AEQ V1) (m2: @mem A AEQ V2) a v,
      addrs_match m1 m2 ->
      m2 a <> None ->
      addrs_match (upd m1 a v) m2.
  Proof.
    unfold addrs_match; intros; simpl.
    destruct (AEQ a a0); subst;
    [rewrite upd_eq in *
    |rewrite upd_ne in *]; eauto.
  Qed.

  Lemma cons_l_neq:
    forall V (l:list V) v,
      ~ v::l = l.
  Proof.
    induction l; simpl; intros; try congruence.
  Qed.

  Lemma mem_union_some_l:
    forall AT AEQ V (m1: @mem AT AEQ V) m2 a v,
      m1 a = Some v ->
      mem_union m1 m2 a = Some v.
  Proof.
    unfold mem_union; simpl; intros.
    cleanup; eauto.
  Qed.
  
  Lemma mem_union_some_r:
    forall AT AEQ V (m1: @mem AT AEQ V) m2 a,
      m1 a = None ->
      mem_union m1 m2 a = m2 a.
  Proof.
    unfold mem_union; simpl; intros.
    cleanup; eauto.
  Qed.

  Lemma addrs_match_mem_union1 :
    forall A AEQ V (m1 m2: @mem A AEQ V),
      addrs_match m1 (mem_union m1 m2).
  Proof.
    unfold addrs_match; intros.
    destruct_fresh (m1 a); try congruence.
    erewrite mem_union_some_l; eauto.
  Qed.

  Lemma addrs_match_empty_mem:
    forall A AEQ V1 V2 (m: @mem A AEQ V1),
      addrs_match (@empty_mem A AEQ V2) m.
  Proof.
    unfold addrs_match, empty_mem;
    simpl; intros; congruence.
  Qed.
  
  Lemma empty_mem_some_false:
    forall A AEQ V (m: @mem A AEQ V) a v,
      m = empty_mem ->
      m a <> Some v.
  Proof.
    intros.
    rewrite H.
    unfold empty_mem; simpl; congruence.
  Qed.
  
  
Lemma recovery_simulation :
  forall n u,
    SimulationForProgramGeneral _ _ _ _ refinement u _ (|Recover|) (|Recover|)
                         (authenticated_disk_reboot_list n)
                         (file_disk_reboot_list n)
                         refines_to_reboot refines_to.
Proof.
  unfold SimulationForProgramGeneral; induction n; simpl; intros; cleanup.
  {
    destruct l_o_imp; intuition; simpl in *.
    cleanup; intuition.
    invert_exec; simpl in *; cleanup; intuition.
    specialize H2 with (1:= H12).
    cleanup; intuition eauto; cleanup; try unify_execs; cleanup.
    
    eexists; intuition eauto.
    unfold file_disk_reboot_list in *; simpl.
    simpl in *; destruct l; simpl in *; try lia.
    instantiate (1:= RFinished s_abs tt). 
    repeat econstructor.
    {
      simpl.
      unfold refines_to, refines_to_reboot in *.
      eapply H2 in H0; split_ors; cleanup; unify_execs;
      cleanup; eauto.
      econstructor; eauto.
    }
    {
      simpl; eauto.
      eapply recover_finished; eauto.
    }
    simpl; eauto.
    destruct t; eauto.
  }
  {
    invert_exec; simpl in *; cleanup; intuition;
    cleanup; intuition eauto; repeat (unify_execs; cleanup).
    clear H1.
    specialize H2 with (1:= H11).
    cleanup; intuition eauto; cleanup; try unify_execs; cleanup.
    edestruct IHn.
    eauto.
    instantiate (1:= s_abs).
    eauto.
    eauto.
      
    unfold refines_to_reboot, files_reboot_rep in *; simpl in *; cleanup.
    eapply recover_crashed in H11; eauto.
    eauto; cleanup.

    cleanup.
    exists (Recovered (extract_state_r x0)).
    unfold file_disk_reboot_list in *; simpl in *.
    unfold refines_to_reboot, files_reboot_rep in *; cleanup.
    split; eauto.
    repeat econstructor; eauto.
    eapply H3 in H0; split_ors; cleanup; unify_execs;
    cleanup; eauto.
    econstructor; eauto.
  }
Qed.


Lemma read_simulation :
  forall a inum n u,
    SimulationForProgram refinement u (|Read inum a|) (|Recover|)
                         (authenticated_disk_reboot_list n)
                         (file_disk_reboot_list n).
Proof.
  unfold authenticated_disk_reboot_list, SimulationForProgram,
  SimulationForProgramGeneral; simpl; intros; cleanup.
  
    invert_exec; simpl in *; cleanup; intuition;
    cleanup; try solve [intuition eauto; try congruence;
                        unify_execs; cleanup].
    {
      specialize H1 with (1:= H10).
      cleanup; intuition eauto; cleanup; try unify_execs; cleanup.
      eapply_fresh read_finished in H10; cleanup; eauto.
      
      destruct n; simpl in *; try congruence; cleanup.
      destruct l; simpl in *; try lia.
      split_ors; cleanup.
      {
        exists (RFinished s_abs None);
        simpl; repeat (split; eauto).
        eapply ExecFinished.
        eapply H4 in H0; destruct H0; cleanup; unify_execs;
        cleanup; eauto.
        econstructor; eauto.
        repeat split_ors; cleanup;
        econstructor; eauto.
      }
      {
        exists (RFinished s_abs (nth_error x0.(blocks) a));
        simpl; intuition eauto.
        eapply ExecFinished.
        eapply H4 in H0; destruct H0; cleanup; unify_execs;
        cleanup; eauto.        
        destruct_fresh (nth_error (blocks x0) a);
        do 2 econstructor; eauto.
      }
    }
    {
      clear H1.
      specialize H3 with (1:= H9).
      cleanup; intuition eauto; cleanup; try unify_execs; cleanup.
      destruct n; simpl in *; try congruence; cleanup.

      eapply_fresh read_crashed in H9; eauto.
      edestruct recovery_simulation; eauto.
      
      exists (Recovered (extract_state_r x0)); simpl; intuition eauto.
      unfold file_disk_reboot_list; simpl.
      eapply ExecRecovered; eauto.
      eapply H3 in H0; destruct H0; cleanup; try unify_execs;
      cleanup; eauto.
      repeat econstructor.
    }
    Unshelve.
    all: repeat econstructor; eauto.
Qed.

Require Import Compare_dec.


Lemma write_simulation :
  forall inum a v n u,
    SimulationForProgram refinement u (|Write inum a v|) (|Recover|)
                         (authenticated_disk_reboot_list n)
                         (file_disk_reboot_list n).
Proof.
  unfold authenticated_disk_reboot_list, SimulationForProgram,
  SimulationForProgramGeneral; simpl; intros; cleanup.
  
    invert_exec; simpl in *; cleanup; intuition;
    cleanup; try solve [intuition eauto; try congruence;
                        unify_execs; cleanup].
    {
      specialize H1 with (1:= H10).
      cleanup.
      eapply_fresh H4 in H0; clear H4;cleanup;
      do 2 (split_ors; cleanup); try unify_execs;
      cleanup; eauto;
      cleanup; repeat (split_ors; cleanup);
      try unify_execs; cleanup;
     
      destruct n; simpl in *; try congruence; cleanup;
      destruct l; simpl in *; try lia;
      
      eapply_fresh write_finished in H10; eauto;
      repeat split_ors; cleanup; try congruence; try lia; 
      try solve [
        exists (RFinished s_abs None);
        simpl; repeat (split; eauto);
        eapply ExecFinished;
        repeat split_ors; cleanup;
        do 2 econstructor; eauto ];
      try solve [
        exists (RFinished  (Mem.upd s_abs inum (update_file x a v)) (Some tt));
        simpl; repeat (split; eauto);
        eapply ExecFinished;
        repeat split_ors; cleanup;
        do 2 econstructor; eauto ].
    }
    {
      clear H1.
      specialize H3 with (1:= H9).
      cleanup; intuition eauto; cleanup; try unify_execs; cleanup;
      repeat split_ors; cleanup; try unify_execs; cleanup.
      destruct n; simpl in *; try congruence; cleanup.
      {
        eapply_fresh write_crashed in H9; eauto;
        repeat split_ors; cleanup; try unify_execs; cleanup;
        edestruct recovery_simulation; eauto; cleanup.
        
        {
          exists (Recovered (extract_state_r x0)); simpl; split; eauto.
          unfold file_disk_reboot_list; simpl.
          eapply_fresh H3 in H0; clear H3; cleanup;
          do 2 (split_ors; cleanup); try unify_execs;
          cleanup; eauto;
          try solve [eapply ExecRecovered; eauto;
                     repeat econstructor; eauto].

        
          eapply files_crash_rep_eq in H1; eauto; cleanup. 
          eapply ExecRecovered.
          repeat econstructor; eauto.
          setoid_rewrite H1; eauto.
        }
        {
           exists (Recovered (extract_state_r x1)); simpl; split; eauto.
           unfold file_disk_reboot_list; simpl.
           eapply_fresh H3 in H0; clear H3; cleanup;
           do 2 (split_ors; cleanup); try unify_execs;
           cleanup; eauto;
           try solve [eapply ExecRecovered; eauto;
                      repeat econstructor; eauto].
           
           
           eapply files_crash_rep_eq in H7; eauto. 
           eapply ExecRecovered.
           repeat econstructor; eauto.
           setoid_rewrite H7; eauto.
        }
      }
    }
    Unshelve.
    all: repeat econstructor; eauto.
    exact (owner x2). 
Qed.


Lemma extend_simulation :
  forall n inum v u,
    SimulationForProgram refinement u (|Extend inum v|) (|Recover|)
                         (authenticated_disk_reboot_list n)
                         (file_disk_reboot_list n).
Proof.
  unfold authenticated_disk_reboot_list, SimulationForProgram,
  SimulationForProgramGeneral; simpl; intros; cleanup.
  
  invert_exec; simpl in *; cleanup; intuition;
  cleanup; try solve [intuition eauto; try congruence;
                      unify_execs; cleanup].
  {
    specialize H1 with (1:= H10).
    cleanup.
    eapply_fresh H4 in H0; clear H4;cleanup;
    do 2 (split_ors; cleanup); try unify_execs;
    cleanup; eauto;
    cleanup; repeat (split_ors; cleanup);
    try unify_execs; cleanup;
    
    destruct n; simpl in *; try congruence; cleanup;
    destruct l; simpl in *; try lia;
    
    eapply_fresh extend_finished in H10; eauto;
    repeat split_ors; cleanup; try congruence; try lia; 
    try solve [
          exists (RFinished s_abs None);
            simpl; repeat (split; eauto);
            eapply ExecFinished;
            repeat split_ors; cleanup;
            do 2 econstructor; eauto ];
    try solve [
          exists (RFinished  (Mem.upd s_abs inum (extend_file x v)) (Some tt));
            simpl; repeat (split; eauto);
            eapply ExecFinished;
            repeat split_ors; cleanup;
            do 2 econstructor; eauto ].

    eapply_fresh files_rep_eq in H8; eauto.
    rewrite <- Hx in H6.
    rewrite Mem.upd_eq in H6; eauto; cleanup.
    unfold extend_file in *.
    destruct x; simpl in *; cleanup.
    inversion H1.
    exfalso; eapply app_ne_diag; eauto.
    congruence.
  }
  {
      clear H1.
      specialize H3 with (1:= H9).
      cleanup; intuition eauto; cleanup; try unify_execs; cleanup;
      repeat split_ors; cleanup; try unify_execs; cleanup.
      destruct n; simpl in *; try congruence; cleanup.
      {
        eapply_fresh extend_crashed in H9; eauto;
        repeat split_ors; cleanup; try unify_execs; cleanup;
        edestruct recovery_simulation; eauto; cleanup.
        
        {
          exists (Recovered (extract_state_r x0)); simpl; split; eauto.
          unfold file_disk_reboot_list; simpl.
          eapply_fresh H3 in H0; clear H3; cleanup;
          do 2 (split_ors; cleanup); try unify_execs;
          cleanup; eauto;
          try solve [eapply ExecRecovered; eauto;
                     repeat econstructor; eauto].
          split_ors; cleanup;
          try unify_execs;
          cleanup; eauto.
        
          eapply files_crash_rep_eq in H1; eauto; cleanup. 
          eapply ExecRecovered.
          repeat econstructor; eauto.
          setoid_rewrite H1; eauto.
        }
        {
           exists (Recovered (extract_state_r x1)); simpl; split; eauto.
           unfold file_disk_reboot_list; simpl.
           eapply_fresh H3 in H0; clear H3; cleanup;
           do 2 (split_ors; cleanup); try unify_execs;
           cleanup; eauto;
           try solve [eapply ExecRecovered; eauto;
                      repeat econstructor; eauto].
           split_ors; cleanup;
           try unify_execs;
           cleanup; eauto.
           
           eapply files_crash_rep_eq in H6; eauto. 
           eapply ExecRecovered.
           repeat econstructor; eauto.
           setoid_rewrite H6; eauto.
        }
      }
    }
    Unshelve.
    all: repeat econstructor; eauto.
    exact (owner x2). 
Qed.

Lemma change_owner_simulation :
  forall n inum own u,
    SimulationForProgram refinement u (|ChangeOwner inum own|) (|Recover|)
                         (authenticated_disk_reboot_list n)
                         (file_disk_reboot_list n).
Proof.
  unfold authenticated_disk_reboot_list, SimulationForProgram,
  SimulationForProgramGeneral; simpl; intros; cleanup.
  
  invert_exec; simpl in *; cleanup; intuition;
  cleanup; try solve [intuition eauto; try congruence;
                      unify_execs; cleanup].
  {
    specialize H1 with (1:= H10).
    cleanup.
    eapply_fresh H4 in H0; clear H4;cleanup;
    do 2 (split_ors; cleanup); try unify_execs;
    cleanup; eauto;
    cleanup; repeat (split_ors; cleanup);
    try unify_execs; cleanup;
    
    destruct n; simpl in *; try congruence; cleanup;
    destruct l; simpl in *; try lia;
    
    eapply_fresh change_owner_finished in H10; eauto;
    repeat split_ors; cleanup; try congruence; try lia; 
    try solve [
          exists (RFinished s_abs None);
            simpl; repeat (split; eauto);
            eapply ExecFinished;
            repeat split_ors; cleanup;
            do 2 econstructor; eauto ];
    try solve [
          exists (RFinished  (Mem.upd s_abs inum (change_file_owner x own)) (Some tt));
            simpl; repeat (split; eauto);
            eapply ExecFinished;
            repeat split_ors; cleanup;
            do 2 econstructor; eauto ].
  }
  {
    clear H1.
    specialize H3 with (1:= H9).
    cleanup; intuition eauto; cleanup; try unify_execs; cleanup;
    repeat split_ors; cleanup; try unify_execs; cleanup.
    destruct n; simpl in *; try congruence; cleanup.
    {
      eapply_fresh change_owner_crashed in H9; eauto;
      repeat split_ors; cleanup; try unify_execs; cleanup;
      edestruct recovery_simulation; eauto; cleanup.
      
      {
        exists (Recovered (extract_state_r x0)); simpl; split; eauto.
        unfold file_disk_reboot_list; simpl.
        eapply_fresh H3 in H0; clear H3; cleanup;
        do 2 (split_ors; cleanup); try unify_execs;
        cleanup; eauto;
        try solve [eapply ExecRecovered; eauto;
                   repeat econstructor; eauto].
        
        eapply files_crash_rep_eq in H1;
        eauto; cleanup. 
        eapply ExecRecovered.
        repeat econstructor; eauto.
        setoid_rewrite H1; eauto.
      }
      {
        exists (Recovered (extract_state_r x1)); simpl; split; eauto.
        unfold file_disk_reboot_list; simpl.
        eapply_fresh H3 in H0; clear H3; cleanup;
        do 2 (split_ors; cleanup); try unify_execs;
        cleanup; eauto;
        try solve [eapply ExecRecovered; eauto;
                   repeat econstructor; eauto].
        
        eapply files_crash_rep_eq in H6; eauto. 
        eapply ExecRecovered.
        repeat econstructor; eauto.
        setoid_rewrite H6; eauto.
      }
    }
  }
  Unshelve.
  all: repeat econstructor; eauto.
Qed.



Lemma delete_simulation :
  forall n inum u,
    SimulationForProgram refinement u (|Delete inum|) (|Recover|)
                         (authenticated_disk_reboot_list n)
                         (file_disk_reboot_list n).
Proof.
  unfold authenticated_disk_reboot_list, SimulationForProgram,
  SimulationForProgramGeneral; simpl; intros; cleanup.
  
  invert_exec; simpl in *; cleanup; intuition;
  cleanup; try solve [intuition eauto; try congruence;
                      unify_execs; cleanup].
  {
    specialize H1 with (1:= H10).
    cleanup.
    eapply_fresh H4 in H0; clear H4;cleanup;
    do 2 (split_ors; cleanup); try unify_execs;
    cleanup; eauto;
    cleanup; repeat (split_ors; cleanup);
    try unify_execs; cleanup;
    
    destruct n; simpl in *; try congruence; cleanup;
    destruct l; simpl in *; try lia;
    
    eapply_fresh delete_finished in H10; eauto;
    repeat split_ors; cleanup; try congruence; try lia; 
    try solve [
          exists (RFinished s_abs None);
            simpl; repeat (split; eauto);
            eapply ExecFinished;
            repeat split_ors; cleanup;
            do 2 econstructor; eauto ];
    try solve [
          exists (RFinished  (Mem.delete s_abs inum) (Some tt));
            simpl; repeat (split; eauto);
            eapply ExecFinished;
            repeat split_ors; cleanup;
            do 2 econstructor; eauto ].
  }
  {
    clear H1.
    specialize H3 with (1:= H9).
    cleanup; intuition eauto; cleanup; try unify_execs; cleanup;
    repeat split_ors; cleanup; try unify_execs; cleanup.
    destruct n; simpl in *; try congruence; cleanup.
    {
      eapply_fresh delete_crashed in H9; eauto;
      repeat split_ors; cleanup; try unify_execs; cleanup;
      edestruct recovery_simulation; eauto; cleanup.
      
      {
        exists (Recovered (extract_state_r x0)); simpl; split; eauto.
        unfold file_disk_reboot_list; simpl.
        eapply_fresh H3 in H0; clear H3; cleanup;
        do 2 (split_ors; cleanup); try unify_execs;
        cleanup; eauto;
        try solve [eapply ExecRecovered; eauto;
                   repeat econstructor; eauto].
        
        eapply files_crash_rep_eq in H1;
        eauto; cleanup. 
        eapply ExecRecovered.
        repeat econstructor; eauto.
        setoid_rewrite H1; eauto.
      }
      {
        exists (Recovered (extract_state_r x1)); simpl; split; eauto.
        unfold file_disk_reboot_list; simpl.
        eapply_fresh H3 in H0; clear H3; cleanup;
        do 2 (split_ors; cleanup); try unify_execs;
        cleanup; eauto;
        try solve [eapply ExecRecovered; eauto;
                   repeat econstructor; eauto].
        
        eapply files_crash_rep_eq in H6; eauto. 
        eapply ExecRecovered.
        repeat econstructor; eauto.
        setoid_rewrite H6; eauto.
      }
    }
  }
  Unshelve.
  all: repeat econstructor; eauto.
  exact (owner x2).
Qed.




Lemma create_simulation :
  forall n own u,
    SimulationForProgram refinement u (|Create own|) (|Recover|)
                         (authenticated_disk_reboot_list n)
                         (file_disk_reboot_list n).
Proof.
  unfold addr, authenticated_disk_reboot_list,
  SimulationForProgram,
  SimulationForProgramGeneral; simpl; intros; cleanup.
  
  invert_exec; simpl in *; cleanup; intuition;
  cleanup; try solve [intuition eauto; try congruence;
                      unify_execs; cleanup].  
  {
    specialize H1 with (1:= H10).
    cleanup.
    eapply_fresh H4 in H0; clear H4;cleanup;
    do 2 (split_ors; cleanup); try unify_execs;
    cleanup; eauto;
    cleanup; repeat (split_ors; cleanup);
    try unify_execs; cleanup;
    
    destruct n; simpl in *; try congruence; cleanup;
    destruct l; simpl in *; try lia;
    
    eapply_fresh create_finished in H10; eauto;
    repeat split_ors; cleanup; try congruence; try lia; 
    try solve [
          exists (RFinished s_abs None);
            simpl; repeat (split; eauto);
            eapply ExecFinished;
            repeat split_ors; cleanup;
            do 2 econstructor; eauto ].
    try solve [
          exists (RFinished  (Mem.upd s_abs x (new_file own)) (Some x));
            simpl; repeat (split; eauto);
            eapply ExecFinished;
            repeat split_ors; cleanup;
            do 2 econstructor; eauto ].
  }
  {
    clear H1.
    specialize H3 with (1:= H9).
    cleanup; intuition eauto; cleanup; try unify_execs; cleanup;
    repeat split_ors; cleanup; try unify_execs; cleanup.
    destruct n; simpl in *; try congruence; cleanup.
    {
      eapply_fresh create_crashed in H9; eauto;
      repeat split_ors; cleanup; try unify_execs; cleanup;
      edestruct recovery_simulation; eauto; cleanup.
      
      {
        exists (Recovered (extract_state_r x0)); simpl; split; eauto.
        unfold file_disk_reboot_list; simpl.
        eapply_fresh H3 in H0; clear H3; cleanup;
        do 2 (split_ors; cleanup); try unify_execs;
        cleanup; eauto;
        try solve [eapply ExecRecovered; eauto;
                   repeat econstructor; eauto].
        
        eapply files_crash_rep_eq in H1;
        eauto; cleanup. 
        eapply ExecRecovered.
        repeat econstructor; eauto.
        setoid_rewrite H1; eauto.
      }
      {
        exists (Recovered (extract_state_r x1)); simpl; split; eauto.
        unfold file_disk_reboot_list; simpl.
        eapply_fresh H3 in H0; clear H3; cleanup;
        do 2 (split_ors; cleanup); try unify_execs;
        cleanup; eauto;
        try solve [eapply ExecRecovered; eauto;
                   repeat econstructor; eauto].
        
        eapply files_crash_rep_eq in H5; eauto. 
        eapply ExecRecovered.
        repeat econstructor; eauto.
        setoid_rewrite H5; eauto.

        eapply files_crash_rep_eq in H5; eauto. 
        eapply ExecRecovered.
        repeat econstructor; eauto.
        setoid_rewrite H5; eauto.
      }
    }
  }
  Unshelve.
  all: repeat econstructor; eauto.
Qed.



End FileDiskSimulation.


(*
Section TransferToTransactionCache.

Lemma high_oracle_exists_ok:
    high_oracle_exists refinement.
Proof.
  unfold high_oracle_exists; simpl.
  induction p2; simpl; intros; cleanup.
  { (** Op p **)
    destruct p; simpl in *.
    { (** Start **)
      destruct s1'.
      { (** Finished **)
        eapply exec_to_sp with (P := fun o s => refines_to s x /\ o = o1 /\ s = s1) in H0 as Hx; eauto.
        simpl in *; cleanup.
        do 2 eexists; intuition eauto.
        left; do 2 eexists; intuition eauto.
        destruct s; simpl in *; subst; eauto.
      }
      { (** Crashed **)
        eapply exec_to_scp with (P := fun o s => refines_to s x /\ o = o1 /\ s = s1) in H0 as Hx; eauto.
        simpl in *; cleanup.
        split_ors; cleanup; repeat (simpl in *; try split_ors; cleanup);
        try (inversion H1; clear H1); cleanup; eauto;
        try solve [
              do 2 eexists; intuition eauto;
              right; do 2 eexists; intuition eauto;
             destruct s; simpl in *; cleanup; eauto ].
      }
    }
    { (** Read **)
      destruct s1'.
      { (** Finished **)
        eapply exec_to_sp with (P := fun o s => refines_to s x /\ o = o1 /\ s = s1) in H0 as Hx; eauto.
        unfold read in Hx; simpl in Hx; cleanup;
        cleanup; simpl in *; cleanup;
        do 2 eexists; intuition eauto;
        left; do 2 eexists; intuition eauto;
        destruct s; cleanup; simpl in *; cleanup; eauto.
      }
      { (** Crashed **)
        eapply exec_to_scp with (P := fun o s => refines_to s x /\ o = o1 /\ s = s1) in H0 as Hx; eauto.
        unfold read in Hx; repeat (simpl in *; cleanup).
        split_ors; cleanup; repeat (simpl in *; try split_ors; cleanup);
        try (inversion H1; clear H1); cleanup; eauto;
        try solve [             
           do 2 eexists; intuition eauto;
           right; do 2 eexists; intuition eauto;
           destruct s; simpl in *; cleanup; eauto ].
      
        do 2 eexists; intuition eauto;
        right; do 2 eexists; intuition eauto;
        destruct s; simpl in *; cleanup; eauto.       
      }
    }
    { (** Write **)
      destruct s1'.
      { (** Finished **)
        eapply exec_to_sp with (P := fun o s => refines_to s x /\ o = o1 /\ s = s1) in H0 as Hx; eauto.
        unfold write in Hx; simpl in *; cleanup;
        cleanup; simpl in *; cleanup;      
        try destruct s; cleanup; simpl in *; cleanup; eauto;
        
        do 2 eexists; intuition eauto;
        left; do 2 eexists; intuition eauto;
        try destruct s; cleanup; simpl in *; cleanup; eauto.
        right; right; eexists; intuition eauto.
        omega.
        right; left; intuition eauto.
        omega.
      }
      { (** Crashed **)
        eapply exec_to_scp with (P := fun o s => refines_to s x /\ o = o1 /\ s = s1) in H0 as Hx; eauto.
        unfold write in Hx; repeat (simpl in *; cleanup).
        split_ors; cleanup; repeat (simpl in *; try split_ors; cleanup);
        inversion H1; clear H1; cleanup; eauto;
        try solve [    
              do 2 eexists; intuition eauto;
              right; do 2 eexists; intuition eauto;
              destruct s; simpl in *; cleanup; eauto ].
        do 2 eexists; intuition eauto;
        right; do 2 eexists; intuition eauto;
        destruct s; simpl in *; cleanup; eauto.
      }
    }
    { (** Commit **)
      destruct s1'.
      { (** Finished **)
        eapply exec_to_sp with (P := fun o s => refines_to s x /\ o = o1 /\ s = s1) in H0 as Hx; eauto.
        simpl in *; cleanup.
        cleanup; simpl in *; cleanup;        
        do 2 eexists; intuition eauto;
        left; do 2 eexists; intuition eauto;
        destruct s; cleanup; simpl in *; cleanup; eauto;
        eexists; intuition eauto.
        
        rewrite <- map_fst_split, <- map_snd_split.
        rewrite mem_union_upd_batch_eq; eauto.
        
        exfalso; apply H; apply dedup_last_NoDup.
        

        exfalso; apply H2; apply dedup_last_dedup_by_list_length_le.
        rewrite <- map_fst_split, <- map_snd_split; repeat rewrite map_length; omega.
        unfold refines_to in *; cleanup; simpl in *; eauto.
        cleanup.

         unfold refines_to in *; simpl in *;
         cleanup; exfalso; eauto;
         match goal with
         | [H: addrs_match _ _ |- _ ] =>
           unfold addrs_match in H;
           eapply H
         end; eauto;
         apply apply_list_in_not_none; eauto;
         rewrite map_fst_split; eauto.
    }
    {
      eapply exec_to_scp with (P := fun o s => refines_to s x /\ o = o1 /\ s = s1) in H0 as Hx; eauto.
       simpl in *; cleanup.
       split_ors; cleanup; repeat (simpl in *; try split_ors; cleanup);
       
       try solve [
             inversion H1; clear H1; cleanup; eauto;        
             do 2 eexists; intuition eauto;
             right; do 2 eexists; intuition eauto;
             destruct s; simpl in *; cleanup; eauto ];

       
       try solve [
             try (inversion H1; clear H1; cleanup; eauto);  
             repeat (split_ors; cleanup);
             try solve [
                   exfalso;
                   match goal with
                   | [H: ~ NoDup _ |- _] =>
                     apply H
                   end; apply dedup_last_NoDup ];
             try solve [
                   exfalso;
                   match goal with
                   | [H: ~ length _ = length _ |- _] =>
                     apply H
                   end;
                   apply dedup_last_dedup_by_list_length_le; eauto;        
                   rewrite <- map_fst_split, <- map_snd_split;
                   repeat rewrite map_length; eauto ];
             try solve [
                   unfold refines_to in *; simpl in *;
                   cleanup; exfalso; eauto;
                   match goal with
                   | [H: addrs_match _ _ |- _ ] =>
                     unfold addrs_match in H;
                     eapply H
                   end; eauto;
                   apply apply_list_in_not_none; eauto;
                   rewrite map_fst_split; eauto ];
             
             do 2 eexists; intuition eauto;
             right; do 2 eexists; intuition eauto;
             try solve [
                   right; left; intuition eauto;
                   destruct s; simpl in *; cleanup; eauto;
                   eexists; intuition eauto;        
                   setoid_rewrite mem_union_upd_batch_eq;
                   rewrite mem_union_empty_mem;
                   rewrite map_fst_split, map_snd_split; eauto ];
             try solve [
                   right; right; intuition eauto;
                   destruct s; simpl in *; cleanup; eauto;
                   eexists; intuition eauto;        
                   setoid_rewrite mem_union_upd_batch_eq;
                   rewrite mem_union_empty_mem;
                   rewrite map_fst_split, map_snd_split; eauto ]
           ].
       }
    }
    
  - (** Abort **)
    destruct s1'.
    {
      eapply exec_to_sp with (P := fun o s => refines_to s x /\ o = o1 /\ s = s1) in H0 as Hx; eauto.
      simpl in *; cleanup.
      do 2 eexists; intuition eauto.
      left; do 2 eexists; intuition eauto.
      destruct s; simpl in *; subst; eauto.
    }
    {
      eapply exec_to_scp with (P := fun o s => refines_to s x /\ o = o1 /\ s = s1) in H0 as Hx; eauto.
      simpl in *; cleanup.
       split_ors; cleanup; repeat (simpl in *; try split_ors; cleanup);
       try (inversion H1; clear H1); cleanup; eauto;
       try solve [
             do 2 eexists; intuition eauto;
             right; do 2 eexists; intuition eauto;
             destruct s; simpl in *; cleanup; eauto ].
    }
  }
  - (** Ret **)
    destruct s1'; eexists; eauto.
  - (** Bind **)
    invert_exec.
    + (** Finished **)
      edestruct IHp2; eauto.
      eapply_fresh exec_compiled_preserves_refinement in H1; simpl in *;  eauto.
      cleanup; simpl in *; eauto.
      edestruct H; eauto.
      do 5 eexists; repeat (split; eauto).
      right; eauto.
      do 3 eexists; repeat (split; eauto).
    + (* Crashed *)
      split_ors; cleanup.
      * (* p1 crashed *)
        edestruct IHp2; eauto.
        do 5 eexists; repeat (split; eauto).
      * (* p2 Crashed *)
        edestruct IHp2; eauto.
        eapply_fresh exec_compiled_preserves_refinement in H1; simpl in *; eauto.
        cleanup; simpl in *; eauto.
        edestruct H; eauto.
        do 5 eexists; repeat (split; eauto).
        right; eauto.
        do 3 eexists; repeat (split; eauto).
        Unshelve.
        all: constructor.
Qed.


Theorem transfer_to_TransactionCache:
    forall related_states_h
    valid_state_h
    valid_prog_h,
    
    SelfSimulation
      high
      valid_state_h
      valid_prog_h
      related_states_h ->
    
    oracle_refines_to_same_from_related refinement related_states_h ->

    exec_compiled_preserves_validity refinement                           
    (refines_to_valid refinement valid_state_h) ->
    
    SelfSimulation
      low
      (refines_to_valid refinement valid_state_h)
      (compiles_to_valid refinement valid_prog_h)
      (refines_to_related refinement related_states_h).
Proof.
  intros; eapply transfer_high_to_low; eauto.
  apply sbs.
  apply high_oracle_exists_ok.
Qed.

End TransferToTransactionCache.
*)
