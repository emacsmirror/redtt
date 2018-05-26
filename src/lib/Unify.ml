open RedBasis
open Contextual
open Bwd
open Dev

module Notation = Monad.Notation (Contextual)
open Notation

type telescope = (Name.t * ty) list

let rec telescope ty =
  match Tm.unleash ty with
  | Tm.Pi (dom, cod) ->
    let x, codx = Tm.unbind cod in
    let (tel, ty) = telescope codx in
    (x, dom) :: tel, ty
  | _ ->
    [], ty

let rec lambdas gm tm =
  match gm with
  | [] -> tm
  | (x, _) :: gm ->
    lambdas gm @@ Tm.make @@ Tm.Lam (Tm.bind x tm)

let rec pis gm tm =
  match gm with
  | [] -> tm
  | (x, ty) :: gm ->
    pis gm @@ Tm.make @@ Tm.Pi (ty, Tm.bind x tm)

let define gm alpha ty tm =
  let ty' = pis gm ty in
  let tm' = lambdas gm tm in
  (* In Gundry/McBride, a substitution is also unleashed to the right. We're going to find out if we need it. *)
  pushr @@ E (alpha, ty', Defn tm')

(* This is a crappy version of occurs check, not distingiushing between strong rigid and weak rigid contexts.
   Later on, we can improve it. *)
let occurs_check alpha tm =
  Occurs.Set.mem alpha @@
  Tm.free `Metas tm


let rec eta_contract t =
  match Tm.unleash t with
  | Tm.Lam bnd ->
    let y, tmy = Tm.unbind bnd in
    let tm'y = eta_contract tmy in
    begin
      match Tm.unleash tm'y with
      (* TODO: I think this is backwards:
         FunApp should be at the end of the stack, not at the beginning
      *)
      | Tm.Up (Tm.Cut (Tm.Ref f, Snoc (sp, Tm.FunApp arg))) ->
        begin
          match Tm.unleash arg with
          | Tm.Up (Tm.Cut (Tm.Ref y', Emp))
            when
              y = y'
              && not @@ Occurs.Set.mem y @@ Tm.Sp.free `Vars sp
            ->
            Tm.up @@ Tm.Cut (Tm.Ref f, sp)
          | _ ->
            Tm.make @@ Tm.Lam (Tm.bind y tm'y)
        end
      | _ ->
        Tm.make @@ Tm.Lam (Tm.bind y tm'y)
    end

  | Tm.Cons (t0, t1) ->
    let t0' = eta_contract t0 in
    let t1' = eta_contract t1 in
    begin
      match Tm.unleash t0', Tm.unleash t1' with
      | Tm.Up _, Tm.Up _ ->
        failwith ""
      | _ ->
        failwith "TODO"
    end

  | con ->
    Tm.make @@ Tm.map_tmf eta_contract con

let to_var t =
  match Tm.unleash @@ eta_contract t with
  | Tm.Up (Tm.Cut (Tm.Ref a, Emp)) ->
    Some a
  | _ ->
    None

let rec to_vars ts =
  match ts with
  | [] -> Some []
  | v :: ts ->
    match to_var v with
    | Some x -> Option.map (fun xs -> x :: xs) @@ to_vars ts
    | None -> None

let invert alpha _ty _sp t =
  if occurs_check alpha t then
    failwith "occurs check"
  else (* alpha does not occur in t *)

    failwith "TODO"

let try_invert q ty =
  match Tm.unleash q.tm0 with
  | Tm.Up (Tm.Cut (Meta alpha, sp)) ->
    begin
      invert alpha ty sp q.tm1 >>= function
      | None ->
        ret false
      | Some t ->
        active (Unify q) >>
        define [] alpha ty t >>
        ret true
    end
  | _ ->
    failwith "try_invert"

let rec flex_term ~deps q =
  match Tm.unleash q.tm0 with
  | Tm.Up (Tm.Cut (Meta alpha, _)) ->
    List.map snd <@> ask >>= fun gm ->
    popl >>= fun e ->
    begin
      match e with
      | E (beta, _, Hole) when alpha = beta && Occurs.Set.mem alpha @@ Entries.free `Metas deps ->
        pushls (e :: deps) >>
        block (Unify q)
      | E (beta, ty, Hole) when alpha = beta ->
        pushls deps >>
        try_invert q ty <||
        begin
          block (Unify q) >>
          pushl e
        end
      | E (beta, _, Hole)
        when
          Occurs.Set.mem beta (Params.free `Metas gm)
          || Occurs.Set.mem beta (Entries.free `Metas deps)
          || Occurs.Set.mem beta (Equation.free `Metas q)
        ->
        flex_term ~deps:(e :: deps) q
      | _ ->
        pushr e >>
        flex_term ~deps q
    end
  | _ -> failwith "flex_term"