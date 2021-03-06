open RedBasis.Bwd
open RedTT_Core

type tm = Tm.tm
type ty = Tm.tm

type 'a decl =
  | Hole of [`Rigid | `Flex]
    (** a hole during the development *)
  | Auxiliary of 'a
    (** this means a variable can be expanded into a term,
        and this is not generated by the user. *)
  | UserDefn of
    {source : FileRes.filepath;
     visibility : ResEnv.visibility;
     opacity : [`Transparent | `Opaque];
     tm : 'a}
    (** this is a definition given by the user and has been type-checked *)
  | Guess of {ty : 'a; tm : 'a}
    (** we have a term [tm] of type [ty], which is not yet the same as
        the hole we are trying to fill *)

type status =
  | Blocked
  | Active

type ('a, 'b) equation =
  {ty0 : ty;
   tm0 : 'a;
   ty1 : ty;
   tm1 : 'b}

(* The [param] and [params] types are really dumb; it should not be any kind of list. Instead it should be an ordinary datatype.
   Right now we're going through such stupid contortions to make it a last. For instance, not every cell
   should be binding a variable, lmao! *)
type 'a param =
  [ `I (** a local binder for a dimension variable. *)
  | `NullaryExt (** a local binder that binds nothing but imposes a system. *)
  | `P of 'a (** a local binder for an expression variable. the argument is the type *)
  | `Def of 'a * 'a (** a local binder for user definitions. the first argument is the type and the second is the term. *)
  | `Tw of 'a * 'a (** a local binder which binds a twin variable, with a type for each side of a unification problem *)
  | `R of 'a * 'a (** a local binder that binds nothing but restricts the context. *)
  ]

type params = (Name.t * ty param) bwd

type 'a bind

type problem =
  | Unify of (tm, tm) equation
  | Subtype of {ty0 : ty; ty1 : ty}
  | All of ty param * problem bind

type entry =
  | E of Name.t * ty * tm decl
  | Q of status * problem

val bind : Name.t -> 'a param -> problem -> problem bind
val unbind : 'a param -> problem bind -> Name.t * problem

val inst_with_vars : Name.t list -> problem -> [`Unify of (tm, tm) equation | `Subtype of tm * tm] option


val pp_params : params Pp.t0
val pp_entry : entry Pp.t0


type twin = Tm.twin

module Subst = GlobalEnv

module type DevSort =
sig
  include Occurs.S
  val pp : t Pp.t0
  val subst : Subst.t -> t -> t
end

module Problem :
sig
  include DevSort with type t = problem
  val eqn : ty0:ty -> tm0:tm -> ty1:ty -> tm1:tm -> problem
  val all : Name.t -> ty -> problem -> problem
  val all_twins : Name.t -> ty -> ty -> problem -> problem
  val all_dims : Name.t list -> problem -> problem
end

module Param : DevSort with type t = ty param

module Params : Occurs.S with type t = ty param bwd

module Equation :
sig
  include DevSort with type t = (tm, tm) equation
  val sym : ('a, 'b) equation -> ('b, 'a) equation
end

module Decl : Occurs.S with type t = tm decl

module Entry :
sig
  include DevSort with type t = entry
  val is_incomplete : t -> bool
end

module Entries : Occurs.S with type t = entry list
