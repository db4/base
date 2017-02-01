open! Import

type ('a, 'b) t = T : ('a, 'a) t
type ('a, 'b) equal = ('a, 'b) t

let refl = T

let sym (type a) (type b) (T : (a, b) t) = (T : (b, a) t)

let trans (type a) (type b) (type c) (T : (a, b) t) (T : (b, c) t) = (T : (a, c) t)

let conv (type a) (type b) (T : (a, b) t) (a : a) = (a : b)

module Lift (X : sig type 'a t end) = struct
  let lift (type a) (type b) (T : (a, b) t) = (T : (a X.t, b X.t) t)
end

module Lift2 (X : sig type ('a1, 'a2) t end) = struct
  let lift (type a1) (type b1) (type a2) (type b2) (T : (a1, b1) t) (T : (a2, b2) t) =
    (T : ((a1, a2) X.t, (b1, b2) X.t) t)
  ;;
end

module Lift3 (X : sig type ('a1, 'a2, 'a3) t end) = struct
  let lift (type a1) (type b1) (type a2) (type b2) (type a3) (type b3)
        (T : (a1, b1) t) (T : (a2, b2) t) (T : (a3, b3) t) =
    (T : ((a1, a2, a3) X.t, (b1, b2, b3) X.t) t)
  ;;
end

let detuple2 (type a1) (type a2) (type b1) (type b2)
      (T : (a1 * a2, b1 * b2) t) : (a1, b1) t * (a2, b2) t =
  T, T
;;

let tuple2 (type a1) (type a2) (type b1) (type b2)
      (T : (a1, b1) t) (T : (a2, b2) t) : (a1 * a2, b1 * b2) t =
  T
;;

module type Injective = sig
  type 'a t
  val strip : ('a t, 'b t) equal -> ('a, 'b) equal
end

module type Injective2 = sig
  type ('a1, 'a2)  t
  val strip : (('a1, 'a2) t, ('b1, 'b2) t) equal -> ('a1, 'b1) equal * ('a2, 'b2) equal
end

module Composition_preserves_injectivity (M1 : Injective) (M2 : Injective) = struct
  type 'a t = 'a M1.t M2.t
  let strip e = M1.strip (M2.strip e)
end

module Id = struct
  module Uid = Int

  module Witness = struct
    module Key = struct
      type _ t = ..

      type type_witness_int = [ `type_witness of int ] [@@deriving_inline sexp_of]
      let sexp_of_type_witness_int : type_witness_int -> Sexplib.Sexp.t =
        function
        | `type_witness v0 ->
          Sexplib.Sexp.List [Sexplib.Sexp.Atom "type_witness"; sexp_of_int v0]

      [@@@end]

      let sexp_of_t _sexp_of_a t =
        (`type_witness (Caml.Obj.extension_id (Caml.Obj.extension_constructor t)))
        |> sexp_of_type_witness_int
      ;;
    end

    module type S = sig
      type t
      type _ Key.t += Key : t Key.t
    end

    type 'a t = (module S with type t = 'a)

    let sexp_of_t (type a) sexp_of_a (module M : S with type t = a) =
      M.Key |> Key.sexp_of_t sexp_of_a
    ;;

    let create (type t) () =
      let module M = struct
        type nonrec t = t
        type _ Key.t += Key : t Key.t
      end in
      (module M : S with type t = t)
    ;;

    let uid (type a) (module M : S with type t = a) =
      Caml.Obj.extension_id (Caml.Obj.extension_constructor M.Key)

    (* We want a constant allocated once that [same] can return whenever it gets the same
       witnesses.  If we write the constant inside the body of [same], the native-code
       compiler will do the right thing and lift it out.  But for clarity and robustness,
       we do it ourselves. *)
    let some_t = Some T

    let same (type a) (type b) (a : a t) (b : b t) : (a, b) equal option =
      let module A = (val a : S with type t = a) in
      let module B = (val b : S with type t = b) in
      match A.Key with
      | B.Key -> some_t
      | _     -> None
    ;;
  end


  type 'a t =
    { witness : 'a Witness.t
    ; name    : string
    ; to_sexp : 'a -> Sexp.t
    }
  [@@deriving_inline sexp_of]
  let sexp_of_t : 'a . ('a -> Sexplib.Sexp.t) -> 'a t -> Sexplib.Sexp.t =
    fun _of_a  ->
      function
      | { witness = v_witness; name = v_name; to_sexp = v_to_sexp } ->
        let bnds = []  in
        let arg =
          (fun _f  -> let open Sexplib.Conv in sexp_of_fun ignore) v_to_sexp
        in
        let bnd = Sexplib.Sexp.List [Sexplib.Sexp.Atom "to_sexp"; arg]  in
        let bnds = bnd :: bnds  in
        let arg = sexp_of_string v_name  in
        let bnd = Sexplib.Sexp.List [Sexplib.Sexp.Atom "name"; arg]  in
        let bnds = bnd :: bnds  in
        let arg = Witness.sexp_of_t _of_a v_witness  in
        let bnd = Sexplib.Sexp.List [Sexplib.Sexp.Atom "witness"; arg]  in
        let bnds = bnd :: bnds  in Sexplib.Sexp.List bnds

  [@@@end]

  let to_sexp t x = t.to_sexp x
  let name t = t.name

  let create ~name to_sexp =
    { witness = Witness.create ()
    ; name
    ; to_sexp
    }
  ;;

  let uid t = Witness.uid t.witness

  let hash t = uid t

  let same_witness t1 t2 = Witness.same t1.witness t2.witness

  let same t1 t2 = Option.is_some (same_witness t1 t2)

  let same_witness_exn t1 t2 =
    match same_witness t1 t2 with
    | Some w -> w
    | None ->
      Error.raise_s
        (Sexp.message "Type_equal.Id.same_witness_exn got different ids"
           [ "",
             sexp_of_pair (sexp_of_t sexp_of_opaque) (sexp_of_t sexp_of_opaque) (t1, t2)
           ])
  ;;
end
