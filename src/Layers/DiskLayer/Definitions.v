Require Import Framework.
Import ListNotations.

Set Implicit Arguments.
  
  Inductive token' :=
  | Crash : token'
  | Cont : token'.

  Definition token_dec' : forall (t t': token'), {t=t'}+{t<>t'}.
    decide equality.
  Defined.

  Definition oracle' := list token'.

  Definition state' :=  disk (set value).
  
  Inductive prog' : Type -> Type :=
  | Read : addr -> prog' value
  | Write : addr -> value -> prog' unit.
   
  Inductive exec' :
    forall T, oracle' ->  state' -> prog' T -> @Result state' T -> Prop :=
  | ExecRead : 
      forall d a v,
        read d a = Some v ->
        exec' [Cont] d (Read a) (Finished d v)
             
  | ExecWrite :
      forall d a v,
        read d a <> None ->
        exec' [Cont] d (Write a v) (Finished (write d a v) tt)
 
  | ExecCrash :
      forall T d (p: prog' T),
        exec' [Crash] d p (Crashed d).

  Hint Constructors exec' : core.

  Definition weakest_precondition' T (p: prog' T) :=
   match p in prog' T' return (T' -> state' -> Prop) -> oracle' -> state' -> Prop with
   | Read a =>
     (fun Q o s =>
       exists v,
         o = [Cont] /\
         read s a = Some v /\
         Q v s)
   | Write a v =>
     (fun Q o s =>
       o = [Cont] /\
       read s a <> None /\
       Q tt (write s a v))
   end.

  Definition weakest_crash_precondition' T (p: prog' T) :=
    fun (Q: state' -> Prop) o (s: state') => o = [Crash] /\ Q s.

  Definition strongest_postcondition' T (p: prog' T) :=
   match p in prog' T' return (oracle' -> state' -> Prop) -> T' -> state' -> Prop with
   | Read a =>
     fun P t s' =>
       exists s v,
         P [Cont] s /\
         s' = s /\
         read s a = Some v /\
         t = v
   | Write a v =>
     fun P t s' =>
       exists s,
         P [Cont] s /\
         s' = (write s a v) /\
         read s a <> None /\
         t = tt
   end.

  Definition strongest_crash_postcondition' T (p: prog' T) :=
    fun (P: oracle' -> state' -> Prop) s' => P [Crash] s'.


  Theorem sp_complete':
    forall T (p: prog' T) P (Q: _ -> _ -> Prop),
      (forall t s', strongest_postcondition' p P t s' -> Q t s') <->
      (forall o s s' t, P o s -> exec' o s p (Finished s' t) -> Q t s').
  Proof.
    intros; destruct p; simpl; eauto;
    split; intros;
    try inversion H1; cleanup;
    eapply H; eauto.
    eexists; eauto.
  Qed.

  Theorem scp_complete':
    forall T (p: prog' T) P (Q:  _ -> Prop),
      (forall s', strongest_crash_postcondition' p P s' -> Q s') <->
      (forall o s s', P o s -> exec' o s p (Crashed s') -> Q s').
  Proof.
    intros; destruct p; simpl; eauto;
    split; intros;
    try inversion H1; cleanup;
    eapply H; eauto.
  Qed.


  Theorem wp_complete':
    forall T (p: prog' T) H Q,
      (forall o s, H o s -> weakest_precondition' p Q o s) <->
      (forall o s, H o s -> (exists s' v, exec' o s p (Finished s' v) /\ Q v s')).
  Proof.
    intros; destruct p; simpl; eauto;
    split; intros;
    specialize H0 with (1:= X);
    cleanup; eauto;
    inversion H0; cleanup; eauto.
  Qed.
  
  Theorem wcp_complete':
    forall T (p: prog' T) H C,
      (forall o s, H o s -> weakest_crash_precondition' p C o s) <->
      (forall o s, H o s -> (exists s', exec' o s p (Crashed s') /\ C s')).
  Proof.
    unfold weakest_crash_precondition';
    intros; destruct p; simpl; eauto;
    split; intros;
    specialize H0 with (1:= X);
    cleanup; eauto;
    inversion H0; cleanup; eauto.
  Qed.

  Theorem exec_deterministic_wrt_oracle' :
    forall o s T (p: prog' T) ret1 ret2,
      exec' o s p ret1 ->
      exec' o s p ret2 ->
      ret1 = ret2.
  Proof.
    intros; destruct p; simpl in *; cleanup;
    repeat
      match goal with
      | [H: exec' _ _ _ _ |- _] =>
        inversion H; clear H; cleanup
      end; eauto.
  Qed.
  
  Definition DiskOperation :=
    Build_Operation
      (list_eq_dec token_dec')
      prog'
      exec'
      weakest_precondition'
      weakest_crash_precondition'
      strongest_postcondition'
      strongest_crash_postcondition'
      wp_complete'
      wcp_complete'
      sp_complete'
      scp_complete'
      exec_deterministic_wrt_oracle'.
  
  Definition DiskLang := Build_Language DiskOperation.
  Definition DiskHL := Build_HoareLogic DiskLang.

Notation "| p |" := (Op DiskOperation p)(at level 60).
Notation "x <-| p1 ; p2" := (Bind (Op DiskOperation p1) (fun x => p2))(right associativity, at level 60). 
Notation "p >> s" := (p s) (right associativity, at level 60, only parsing).
