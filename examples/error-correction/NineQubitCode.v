Require Export SQIR.UnitaryOps.

Require Import Common.

Module NineQubitCode.

Local Open Scope ucom.
Local Open Scope nat_scope.

Notation dim := 9%nat.

(** 
  Blocks
 *)

Inductive up_to_three :=
  | Zero 
  | One
  | Two.

Definition t_to_nat (t : up_to_three) : nat :=
  match t with
  | Zero => 0
  | One  => 1
  | Two  => 2
  end.

Definition t_eq (t₁ t₂ : up_to_three) : bool :=
  match t₁, t₂ with
  | Zero, Zero
| One, One
  | Two, Two => true
  | _, _ => false
  end.

Coercion t_to_nat : up_to_three >-> nat.

Definition t_of_nat (n : nat) (h : n < 3) : up_to_three.
Proof.
  destruct n as [| [| [| n']]].
  - exact Zero.
  - exact One.
  - exact Two.
  - lia.
Defined.

(* Encoded blocks *)
Definition block_no := up_to_three.

(* Qubits in a single block *)
Definition block_offset := up_to_three.

Definition block_to_qubit (n : block_no) (off : block_offset) : nat :=
  n * 3 + off.

Compute block_to_qubit (t_of_nat 2 ltac:(lia)) (t_of_nat 2 ltac:(lia)).

(**
  Encoding
 *)

Definition encode_block (n : block_no) : base_ucom dim :=
  let q0 := n * 3 in
  let q1 := q0 + 1 in
  let q2 := q0 + 2 in
  H q0;
  CNOT q0 q1;
  CNOT q0 q2.

Definition encode : base_ucom dim :=
  CNOT 0 3; CNOT 0 6;
  encode_block (t_of_nat 0 ltac:(lia));
  encode_block (t_of_nat 1 ltac:(lia));
  encode_block (t_of_nat 2 ltac:(lia)).

Notation encoded α β := (
    /C2 .* (/√ 2 .* (α .* (3 ⨂ (∣0,0,0⟩ .+            ∣1,1,1⟩))))
 .+ /C2 .* (/√ 2 .* (β .* (3 ⨂ (∣0,0,0⟩ .+  (-1)%R .* ∣1,1,1⟩))))
).

Ltac f_to_vec_simpl_light :=
  first
  [ rewrite f_to_vec_H
  | rewrite f_to_vec_CCX
  | rewrite f_to_vec_CNOT
  ];
  try lia;
  simpl update;
  do 2 (
    repeat rewrite Mmult_plus_distr_l;
    repeat rewrite Mscale_mult_dist_r
  ).

Ltac pull_scalars :=
  repeat rewrite <- Mscale_plus_distr_r;
  repeat rewrite kron_plus_distr_r;
  repeat rewrite kron_plus_distr_l;
  repeat rewrite Mplus_assoc.

Theorem encode_correct : forall (α β : C),
   (@uc_eval dim encode) × ((α .* ∣0⟩ .+ β .* ∣1⟩) ⊗ 8 ⨂ ∣0⟩)
   = encoded α β.
Proof.
  intros.
  simpl. Msimpl_light.

  replace (∣0⟩) with (f_to_vec 1 (fun _ => false)) by lma'.
  replace (∣1⟩) with (f_to_vec 1 (fun _ => true)) by lma'.
  restore_dims.
  rewrite Common.zero_9_f_to_vec.
  rewrite Common.nine_9_f_to_vec.

  repeat rewrite Mmult_assoc.
  rewrite kron_plus_distr_r.
  repeat rewrite Mmult_plus_distr_l.
  distribute_scale.
  repeat rewrite Mscale_mult_dist_r.
  restore_dims.
  repeat rewrite kron_assoc by auto 10 with wf_db.
  repeat (rewrite f_to_vec_merge; restore_dims).
  
  repeat f_to_vec_simpl_light.
  simpl. Msimpl_light.

  replace (0 * PI)%R with 0%R by lra.
  replace (1 * PI)%R with PI by lra.
  autorewrite with Cexp_db.
  group_radicals.
  repeat rewrite Mscale_1_l.

  pull_scalars.
  f_equal.
  - repeat rewrite Mscale_assoc.
    replace (α * / √ 2 * / √ 2 * / √ 2)%C with (/√ 2 * / C2 * α)%C.
    2: {
      (* why does lca not work here? *)
      rewrite Cmult_comm.
      do 2 rewrite <- Cmult_assoc.
      f_equal. f_equal.
      symmetry. apply Cinv_sqrt2_sqrt.
    }
    repeat (rewrite <- kron_assoc by auto 10 with wf_db; restore_dims).
    reflexivity.
  - do 2 (
      repeat rewrite Mscale_assoc;
      repeat rewrite (Cmult_comm (-1)%R _);
      repeat rewrite <- (Mscale_assoc _ _ _ (-1)%R _);
      repeat rewrite <- Mscale_plus_distr_r
    ).
    repeat rewrite Mscale_assoc.
    replace (β * / √ 2 * / √ 2 * / √ 2)%C with (/ √ 2 * / C2 * β)%C.
    2: {
      (* why does lca not work here? *)
      rewrite Cmult_comm.
      do 2 rewrite <- Cmult_assoc.
      f_equal. f_equal.
      symmetry. apply Cinv_sqrt2_sqrt.
    }
    f_equal.
    repeat rewrite Mscale_plus_distr_r.
    distribute_scale.
    repeat (rewrite <- kron_assoc by auto 10 with wf_db; restore_dims).
    repeat rewrite Mplus_assoc.
    reflexivity.
Qed.


(**
  Errors
 *)

Inductive phase_flip_error (n : block_no) : Set :=
  | OnePhaseFlip (off : block_offset)
  | MorePhaseFlip (e : phase_flip_error n) (off : block_offset).

Inductive bit_flip_error : Set :=
  | OneBitFlip (n : block_no) (off : block_offset)
  | TwoBitFlip (n₁ n₂ : block_no) (h : n₁ <> n₂) (off₁ off₂ : block_offset)
  | ThreeBitFlip (off₁ off₂ off₃ : block_offset).

Inductive error : Set :=
  | NoError
  | PhaseFlipError {n} (e : phase_flip_error n)
  | BitFlipError (e : bit_flip_error)
  | PhaseBitErrors {phase_n} (e₁ : phase_flip_error phase_n) (e₂ : bit_flip_error)
  | BitPhaseErrors (e₁ : bit_flip_error) {phase_n} (e₂ : phase_flip_error phase_n).

Fixpoint apply_phase_flip_error {n} (e : phase_flip_error n) : base_ucom dim :=
  match e with
  | OnePhaseFlip _ off => SQIR.Z off
  | MorePhaseFlip _ e off => SQIR.Z off; apply_phase_flip_error e
  end.

Definition apply_bit_flip_error (e : bit_flip_error) : base_ucom dim :=
  match e with
  | OneBitFlip n off => X (block_to_qubit n off)
  | TwoBitFlip n₁ n₂ _ off₁ off₂ => (X (block_to_qubit n₁ off₁)); (X (block_to_qubit n₂ off₂))
  | ThreeBitFlip off₁ off₂ off₃ => (
    let q1 := block_to_qubit (t_of_nat 0 ltac:(lia)) off₁ in
    let q2 := block_to_qubit (t_of_nat 1 ltac:(lia)) off₂ in
    let q3 := block_to_qubit (t_of_nat 2 ltac:(lia)) off₃ in
    X q1; X q2; X q3
  )
  end.

Definition apply_error (e : error) : base_ucom dim :=
  match e with
  | NoError              => SKIP
  | PhaseFlipError    e  => apply_phase_flip_error e
  | BitFlipError      e  => apply_bit_flip_error e
  | PhaseBitErrors e₁ e₂ => apply_phase_flip_error e₁; apply_bit_flip_error e₂
  | BitPhaseErrors e₁ e₂ => apply_bit_flip_error e₁; apply_phase_flip_error e₂
  end.

Fixpoint list_to_map (l : list nat) : nat -> bool :=
  match l with
  | [] => fun _ => false
  | x :: l' => update (list_to_map l') x true
  end.

Fixpoint ancillae_for_phase_flip {n} (e : phase_flip_error n) : list nat :=
  match e with
  | MorePhaseFlip _ (OnePhaseFlip _ _) _ => []
  | MorePhaseFlip _ (MorePhaseFlip _ e _) _ => ancillae_for_phase_flip e
  | OnePhaseFlip _ _ => 
      match n with 
      | Zero => 3 :: [6]
      | One  => [3]
      | Two  => [6]
      end
  end.

Definition block_to_syn (b : block_no) (off : block_offset) : list nat :=
  match off with
  | Zero => b + 1 :: [b + 2]
  | One  => [b + 1]
  | Two  => [b + 2]
  end.

Definition ancillae_for_bit_flip (e : bit_flip_error) : list nat :=
  match e with
| OneBitFlip n off => block_to_syn n off
  | TwoBitFlip n₁ n₂ h off₁ off₂ => 
      match n₁ as n₁', n₂ as n₂' return n₁ = n₁' -> n₂ = n₂' -> list nat with
      | Zero, Zero
      | One, One
      | Two, Two => fun h₁ h₂ => ltac:(
          exfalso;
          subst;
          contradiction
      )
      | n₁', n₂' => fun _ _ => (block_to_syn n₁' off₁) ++ (block_to_syn n₂' off₂)
      end eq_refl eq_refl
  | ThreeBitFlip off₁ off₂ off₃ =>
      (block_to_syn (t_of_nat 0 ltac:(lia)) off₁) ++
      (block_to_syn (t_of_nat 1 ltac:(lia)) off₂) ++
      (block_to_syn (t_of_nat 2 ltac:(lia)) off₃)
  end.

Definition ancillae_for (e : error) : Vector (2 ^ 8) :=
  match e with
  | NoError              => 8 ⨂ ∣0⟩
  | PhaseFlipError e     => f_to_vec 8 (list_to_map (ancillae_for_phase_flip e))
  | BitFlipError e       => f_to_vec 8 (list_to_map (ancillae_for_bit_flip e))
  | PhaseBitErrors e₁ e₂ =>
      f_to_vec 8 (list_to_map (
        ancillae_for_phase_flip e₁ ++
        ancillae_for_bit_flip e₂
      ))
  | @BitPhaseErrors e₁ phase_n e₂ => 
      let v := f_to_vec 8 (list_to_map (
          ancillae_for_bit_flip e₁ ++
          ancillae_for_phase_flip e₂
        )) in
      match e₁ with
      | OneBitFlip n off => 
          if t_eq n phase_n
          then (-1)%R .* v
          else v
      | TwoBitFlip n₁ n₂ _ _ _ =>
          if orb (t_eq n₁ phase_n) (t_eq n₂ phase_n)
          then (-1)%R .* v
          else v
      | ThreeBitFlip _ _ _ => (-1)%R .* v
      end
  end.

Definition decode_block (n : block_no) : base_ucom dim :=
  let q0 := n * 3 in
  let q1 := q0 + 1 in
  let q2 := q0 + 2 in
  CNOT q0 q1;
  CNOT q0 q2;
  CCX q1 q2 q0;
  H q0.

(**
  Decode
 *)
Definition decode : base_ucom dim := 
  decode_block (t_of_nat 0 ltac:(lia));
  decode_block (t_of_nat 1 ltac:(lia));
  decode_block (t_of_nat 2 ltac:(lia));
  CNOT 0 3; CNOT 0 6;
  CCX 6 3 0.

(**
  Full circuit 
 *)
Definition shor (e : error) : base_ucom dim :=
  encode;
  apply_error e;
  (* Does not use the regular:
     `encode; apply_error e; recover; decode` 
     (because we do not recover the original encoding).
     Attempting to do so requires 8 addition
     qubits (really classical bits), 2 per block
     for bit flip, and 2 for phase flip.
     This makes the following analysis rougher.
  *)
  decode.

Lemma inv_sqrt2_cubed : (/ √ 2 * / √ 2 * / √ 2)%C = (/ C2 * /√ 2)%C.
Proof.
  rewrite Cinv_sqrt2_sqrt.
  easy.
Qed.

Ltac compute_vec :=
    simpl uc_eval;
    repeat rewrite Mmult_assoc; restore_dims;
    repeat f_to_vec_simpl_light;
    simpl;
    replace (0 * PI)%R with 0%R by lra;
    replace (1 * PI)%R with PI by lra;
    autorewrite with Cexp_db;
    repeat rewrite Mscale_1_l;
    restore_dims;
    autorewrite with ket_db.

Ltac prep_err_compute :=
  simpl; Msimpl_light; restore_dims;
  rewrite Common.zero_9_f_to_vec, Common.nine_9_f_to_vec;
  repeat (rewrite kron_plus_distr_r, kron_plus_distr_l; restore_dims);
  repeat rewrite kron_plus_distr_r;
  repeat rewrite Mplus_assoc;
  repeat (rewrite Mscale_kron_dist_l; restore_dims);
  repeat rewrite Mscale_kron_dist_r;
  repeat (rewrite Mscale_kron_dist_l; restore_dims);
  repeat (rewrite f_to_vec_merge; restore_dims);

  repeat rewrite Mmult_plus_distr_l;
  repeat rewrite Mscale_mult_dist_r;

  repeat rewrite Mmult_plus_distr_l;
  repeat rewrite Mscale_mult_dist_r;
  restore_dims.


Ltac post_compute_vec :=
    repeat rewrite Cmult_assoc;
    rewrite inv_sqrt2_cubed;
    repeat rewrite <- Mscale_assoc with (y := ((-1)%R : C));
    repeat rewrite <- Mscale_plus_distr_r;
    repeat rewrite <- kron_assoc; auto with wf_db;

    repeat rewrite Mplus_assoc;
    repeat rewrite Mscale_plus_distr_r with (x := ((-1)%R : C));
    repeat rewrite Mplus_assoc.

Definition error_decode_correct_no_error :
  forall (α β : C),
  (@uc_eval dim (apply_error NoError; decode)) × (encoded α β)
  = (α .* ∣0⟩ .+ β .* ∣1⟩) ⊗ ancillae_for NoError.
Proof.
  intros. subst.
  Local Opaque decode CCX.
  simpl ancillae_for. Msimpl_light.
  simpl uc_eval. restore_dims.
  repeat rewrite denote_SKIP; try lia.
  repeat rewrite Mmult_1_l; auto 10 with wf_db.
  restore_dims.
  prep_err_compute.
  Local Transparent decode.

  assert (H1 :
    (uc_eval decode
          × f_to_vec (3 + 3 + 3)
              (fun x : nat =>
               if x <? 3 + 3
               then if x <? 3 then false else false
               else false))
    = (/ C2 * / √ 2 )%C .* ((∣0,0,0⟩ .+ ∣1,0,0⟩) ⊗ (
        ∣0, 0, 0, 0, 0, 0⟩
     .+ ∣0, 0, 0, 1, 0, 0⟩
     .+ ∣1, 0, 0, 0, 0, 0⟩
     .+ ∣1, 0, 0, 1, 0, 0⟩))).
  {
    compute_vec.
    post_compute_vec.
    do 2 rewrite Mplus_comm with (A := ∣ 1, 0, 0, 1, 0, 0, 0, 0, 0 ⟩).
    do 2 rewrite Mplus_comm with (A := ∣ 1, 0, 0, 1, 0, 0, 1, 0, 0 ⟩).
    repeat rewrite Mplus_assoc.
    do 2 rewrite Mplus_comm with (A := ∣ 1, 0, 0, 0, 0, 0, 1, 0, 0 ⟩).
    repeat rewrite Mplus_assoc.
    reflexivity.
  }
  rewrite H1. clear H1.

  assert (H2 :
    (uc_eval decode
              × f_to_vec (3 + 3 + 3)
                  (fun x : nat =>
                   if x <? 3 + 3
                   then if x <? 3 then false else true
                   else false))
    = (
      / C2 * / √ 2
      .* (
        (∣0, 0, 0⟩ ⊗ (∣0, 0, 0, 0, 0, 0⟩ .+ ∣0, 0, 0, 1, 0, 0⟩
                    .+ ∣1, 0, 0, 1, 0, 0⟩ .+ (-1)%R .* ∣1, 0, 0, 0, 0, 0⟩))
      .+ (∣1, 0, 0⟩ ⊗ ((-1)%R .* ∣1, 0, 0, 1, 0, 0⟩ .+           ∣1, 0, 0, 0, 0, 0⟩
                   .+  (-1)%R .* ∣0, 0, 0, 1, 0, 0⟩ .+ (-1)%R .* ∣0, 0, 0, 0, 0, 0⟩))
      )
    )).
  {
    compute_vec.
    replace ((-1)%R * / √ 2)%C with (/ √ 2 * (-1)%R)%C by apply Cmult_comm.
    post_compute_vec.

    do 2 rewrite Mplus_comm with (A := ∣ 0, 0, 0, 1, 0, 0, 1, 0, 0 ⟩).
    repeat rewrite Mplus_assoc.
    reflexivity.
  }
  rewrite H2. clear H2.

  assert (H3 :
    (uc_eval decode
              × f_to_vec (3 + 3 + 3)
                  (fun x : nat =>
                   if x <? 3 + 3
                   then if x <? 3 then true else false
                   else false)) = 9 ⨂ ∣0⟩).
  {
    compute_vec.
    repeat rewrite <- Cmult_assoc.
    rewrite Cmult_comm with (x := ((-1)%R) : C).
    post_compute_vec.
    admit.
  }
  rewrite H3. clear H3.

  assert (H4 :
    (uc_eval decode
              × f_to_vec (3 + 3 + 3)
                  (fun x : nat =>
                   if x <? 3 + 3
                   then if x <? 3 then true else true
                   else false)) = 9 ⨂ ∣0⟩).
  {
    admit.
  }
  rewrite H4. clear H4.

  assert (H5 :
    (uc_eval decode
              × f_to_vec (3 + 3 + 3)
                  (fun x : nat =>
                   if x <? 3 + 3
                   then if x <? 3 then false else false
                   else true)) = 9 ⨂ ∣0⟩).
  {
    admit.
  }
  rewrite H5. clear H5.

  assert (H6 :
    (uc_eval decode
              × f_to_vec (3 + 3 + 3)
                  (fun x : nat =>
                   if x <? 3 + 3
                   then if x <? 3 then false else true
                   else true)) = 9 ⨂ ∣0⟩).
  {
    admit.
  }
  rewrite H6. clear H6.

  assert (H7 :
    (uc_eval decode
              × f_to_vec (3 + 3 + 3)
                  (fun x : nat =>
                   if x <? 3 + 3
                   then if x <? 3 then true else false
                   else true)) = 9 ⨂ ∣0⟩).
  {
    admit.
  }
  rewrite H7. clear H7.

  assert (H8 :
    (uc_eval decode
              × f_to_vec (3 + 3 + 3)
                  (fun x : nat =>
                   if x <? 3 + 3
                   then if x <? 3 then true else true
                   else true)) = 9 ⨂ ∣0⟩).
  {
    admit.
  }
  rewrite H8. clear H8.

  restore_dims.
  
Admitted.


Definition shor_correct (e : error) : forall (α β : C),
  (@uc_eval dim (shor e)) × ((α .* ∣0⟩ .+ β .* ∣1⟩) ⊗ 8 ⨂ ∣0⟩)
  = (α .* ∣0⟩ .+ β .* ∣1⟩) ⊗ ancillae_for e.
Proof.
  intros.
  Local Opaque encode decode apply_error CCX.
  simpl uc_eval.
  repeat rewrite Mmult_assoc.
  rewrite encode_correct.

  destruct e.
  - simpl ancillae_for.
    specialize (error_decode_correct_no_error α β) as H.
    simpl uc_eval in H.
    simpl ancillae_for in H.
    rewrite Mmult_assoc in H.
    apply H.
  - 
Admitted.

End NineQubitCode.
