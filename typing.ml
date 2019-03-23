open Binding
open Environment
open GrammarCommon
open HGrammar
open HtyStore
open TargetEnvListMap
open Type
open Utilities

class typing (hg : hgrammar) = object(self)
  (* --- registers --- *)

  (** nt_ity[nt] has all typings of nonterminal nt. *)
  val nt_ity : ity array = Array.make hg#nt_count TyList.empty

  (** htys[id] contains list of types derived under some environment for
      corresponding terms in the list of terms identified by id. *)
  val hty_store : hty_store = new hty_store hg

  (* --- printing --- *)
  
  (** Used only for verbose printing; global in order to not pass additional argument when not
      verbose printing. *)
  val mutable indent = 0

  (* --- getting registered typings --- *)

  method nt_ty_exists (nt : nt_id) (ty : ty) : bool =
    TyList.exists (fun nt_ty -> nt_ty = ty) nt_ity.(nt)

  method nt_ity (nt : nt_id) : ity = nt_ity.(nt)

  (* --- saving new typings --- *)

  method add_nt_ity (nt : nt_id) (ity : ity) : bool =
    let new_ity_count = ref @@ TyList.length ity in
    nt_ity.(nt) <- TyList.merge_custom (fun x _ ->
        new_ity_count := !new_ity_count - 1;
        x
      ) nt_ity.(nt) ity;
    !new_ity_count <> 0

  method add_nt_ty (nt : nt_id) (ty : ty) : bool =
    self#add_nt_ity nt @@ TyList.singleton ty

  method add_hterms_hty (id : hterms_id) (hty : hty) : bool =
    hty_store#add_hty id hty

  (* --- generating envs --- *)

  (** Returns envs where each env in postfixes is prepended with exactly one hty from prefixes
      in every combination. *)
  method private mk_prod_hty_bindings (i, j : int * int) (prefixes : hty list)
      (postfixes : hty binding list) (acc : hty binding list) : hty binding list =
    match prefixes with 
    | [] -> acc
    | prefix :: prefixes' ->
      let acc' = List.fold_left (fun acc postfix ->
          ((i, j, prefix) :: postfix) :: acc
        ) acc postfixes
      in
      self#mk_prod_hty_bindings (i, j) prefixes' postfixes acc'

  (** Converts bindings in the form "hterms identified by id are substituted for arguments i-j"
      into bindings in the form "arguments i-j have the types <list of types>". *)
  method binding2hty_bindings (mask : vars option) (binding : hterms_id binding)
      (fixed_hterms_hty : (hterms_id * hty) option) : hty binding list =
    let mask, mask_size = match mask with
      | None -> (None, 0)
      | Some mask ->
        let mask_size = SortedVars.length mask in
        if mask_size = 0 || mask_size <> hg#nt_arity (snd @@ SortedVars.hd mask) then
          (Some mask, mask_size)
        else
          (None, mask_size)
    in
    (* Replaces hty on indexes not mentioned in vars by T. *)
    let rec apply_hty_mask mask index acc hty =
      match hty with
      | [] -> List.rev acc
      | ity :: hty' ->
        if SortedVars.is_empty mask || snd (SortedVars.hd mask) <> index then
          apply_hty_mask mask (index + 1) (ity_top :: acc) hty'
        else
          apply_hty_mask mask (index + 1) (ity :: acc) hty'
    in
    match fixed_hterms_hty with
    | Some (fixed_id, fixed_hty) ->
      let htys_raw_binding : (int * int * hty list * bool) list=
        fold_left_short_circuit_after_first [] binding [] (fun acc (i, j, id) ->
            match hty_store#get_htys id with
            | [] -> []
            | htys ->
              let htys, fixed_hty = match j - i - mask_size, mask with
                | 0, _ | _, None -> htys, fixed_hty
                | _, Some vars ->
                  (remove_hty_duplicates @@ List.rev_map (apply_hty_mask vars 0 []) htys,
                   apply_hty_mask vars 0 [] fixed_hty)
              in
              if id = fixed_id then
                (i, j, htys |> List.filter (fun hty -> not @@ hty_eq hty fixed_hty), true) :: acc
              else
                (i, j, htys, false) :: acc
          )
      in
      let fixed_bindings, non_fixed_bindings =
        htys_raw_binding |> List.partition (fun (_, _, _, fixed) -> fixed)
      in
      let fixed_bindings_htys_product : hty list list = product_with_one_fixed
          (fixed_bindings |> List.rev_map (fun (_, _, htys, _) -> htys))
          fixed_hty
      in
      let fixed_bindings_product : hty binding list =
        fixed_bindings_htys_product |> List.rev_map (fun htys ->
            List.rev_map2 (fun hty (i, j, _, _) ->
                (i, j, hty)
              ) htys fixed_bindings
          )
      in
      let non_fixed_bindings : hty binding list =
        List.fold_left (fun acc (i, j, htys, _) ->
            List.rev_map (fun hty -> (i, j, hty)) htys :: acc
          ) [] non_fixed_bindings
      in
      product @@ non_fixed_bindings @ fixed_bindings_product
    | None ->
      product @@ fold_left_short_circuit_after_first [] binding [] (fun acc (i, j, id) ->
          match hty_store#get_htys id with
          | [] -> []
          | htys ->
            let htys = match j - i - mask_size, mask with
              | 0, _ | _, None -> htys
              | _, Some vars ->
                remove_hty_duplicates @@ List.rev_map (apply_hty_mask vars 0 []) htys
            in
            List.rev_map (fun hty -> (i, j, hty)) htys :: acc
        )

(* TODO move and edit docs to above
    (* Returns hty bindings and whether fixed typing of a hterms was applied. Takes hterms
       binding and whether fixed typing was already applied before. If there is fixed typing,
       it applies it in all combination where it is applied at least once. *)
    let rec binding2hty_bindings_aux binding force_fixed_binding =
      match binding with
      | [] -> ([[]], false)
      | [(i, j, id)] ->
        let htys = hty_store#get_htys id in
        let htys = match fixed_hterms_binding with
          | Some (fixed_id, fixed_hty) ->
            if id = fixed_id then
              if force_fixed_binding then
                ([fixed_hty], true)
              else
                (fixed_hty :: htys, true)
            else
              (htys, false)
          | None -> (htys, false)
        in
****************
        let htys = match j - i - mask_size, mask with
          | 0, _ | _, None -> htys
          | _, Some vars ->
            (remove_hty_duplicates @@ List.map (apply_hty_mask vars 0 []) @@ fst htys, snd htys)
*************
        in
        (List.map (fun hty -> [(i, j, hty)]) @@ fst htys, snd htys)
      | (i, j, id) :: binding' ->
        match hty_store#get_htys id with
        | [] -> ([], false) (* short-circuit *)
        | htys ->
          (* recursively get all bindings without using current application info *)
          match binding2hty_bindings_aux binding' force_fixed_binding with
          | [], _ -> ([], false) (* custom to not make many mk_prod_hty_bindings iterations *)
          | hty_binding ->
            (* Make product with the current application info - each typing of hterm with
               identifier id is valid for range i-j, so the output is all possible bindings
               constructed by prepending one of possible types for i-j to any of current bindings.
               This may blow up the number of possible type bindings. *)
            self#mk_prod_hty_bindings (i, j) htys hty_binding []
*)
                                                      
  (** Converts binding to possible environments using information on possible typings of hterms
      flowing into given variables without regard for the context in which they were typed.
      If mask is not None then only variables with specified indexes will be in the environment
      and other will have type T. This can reduce the cost of creating the environment, as
      replacing types with T can generate duplicates that are removed before computing a product.
      This does not return duplicate environments, as it is the product of unique typings taken
      from htys and hty_store does not store duplicates.
      If fixed_var_ity is not None, then only bindings with that type for given variables are
      returned. *)
  method binding2envl (var_count : int) (mask : vars option)
      (fixed_hterms_hty : (hterms_id * hty) option) (binding : hterms_id binding) : envl =
    EnvList.of_list_default_flags @@
    List.map (hty_binding2env var_count) @@
    self#binding2hty_bindings mask binding fixed_hterms_hty

  (* --- typing --- *)
  
  method terminal_ity : terminal -> ity =
    let np = TyList.singleton NP in
    let pr = TyList.singleton PR in
    let a_ity = TyList.of_list [
        mk_fun np PR;
        mk_fun pr PR
      ] in
    let b_ity = TyList.of_list [
        mk_fun np (mk_fun TyList.empty NP);
        mk_fun pr (mk_fun TyList.empty NP);
        mk_fun TyList.empty (mk_fun np NP);
        mk_fun TyList.empty (mk_fun pr NP)
      ] in
    let e_ity = np in
    function
    | A -> a_ity
    | B -> b_ity
    | E -> e_ity

  (** Returns sorted list of typings available for given head term. *)
  method infer_head_ity (h : head) (env_data : (env, int) either) : ity =
    match h with
    | HNT nt -> nt_ity.(nt)
    | HVar v ->
      begin
        match env_data with
        | Left env -> env#get_var_ity v
        | Right _ -> failwith "Expected environment provided for a term with head variables"
      end
    | HT a -> self#terminal_ity a

  method is_nonproductive_app_head_ty (ty : ty) (arity : int) : bool =
    let arg_itys, res_ty = ty2list ty arity in
    not (is_productive res_ty) &&
    not (List.exists (fun ity -> TyList.exists is_productive ity) arg_itys)

  (** Assume that the target is
      /\_i t_1i -> .. -> /\_i t_ki -> t
      with t = pr or np. Typings of h that could make the application have the target type are
      * -> .. -> * -> /\_i t_1i -> .. -> /\_i t_ki -> *
      with some restrictions. If target = NP then t = np, but any * could be valid without
      additional information about duplication. If t = PR then t = pr or at least one of * is
      pr. *)
  method filter_compatible_heads (ity : ity) (arity : int) (target : ty) : ity =
    if is_productive target then
      let flipped_target = flip_productivity target in
      TyList.filter (fun ty ->
          let arg_itys, res_ty = ty2list ty arity in
          eq_ty res_ty target ||
          eq_ty res_ty flipped_target &&
          List.fold_left (fun acc ity ->
              TyList.fold_left (fun acc ty ->
                  if is_productive ty then
                    acc + 1
                  else
                    acc
                ) acc ity
            ) 0 arg_itys >= 1
        ) ity
    else
      TyList.filter (fun ty ->
          let res_ty = remove_args ty arity in
          eq_ty res_ty target
        ) ity

  (** Creates a list of arrays of pairs (term, ity) with ity being intersection type for given
      argument, and each element of outer list corresponds to one of provided types.
      Combines that in a tuple with the rest of the type and a boolean whether the whole type
      is productive. *)
  method annotate_args : 'a. 'a list -> ity -> (('a * ity) list * ty * bool) list =
    fun terms ->
    let rec annotate_args_ty terms ty acc =
      match terms, ty with
      | term :: terms', Fun (_, ity, ty') ->
        annotate_args_ty terms' ty' ((term, ity) :: acc)
      | [], _ ->
        (List.rev acc, ty, is_productive ty)
      | _ -> failwith "List of terms longer than list of arguments in the type"
    in
    TyList.map (fun ty ->
        annotate_args_ty terms ty []
      )
        
  (** Infer variable environments under which type checking of hterm : target succeeds. If target
      is not specified, environments are inferred for all possible targets. Types of variables
      are looked up in the supplied in env_data environment or inferred if only the number of
      variables is provided in env_data. Inference of variable types requires no head variables
      present in hterm.
      Flag no_pr_vars prevents inference of productive variables. Flag force_pr_var ensures that
      there is at least one productive variable. Only one of these flags may be true. *)
  method type_check (hterm : hterm) (target : ty option) (env_data : (env, int) either)
      (no_pr_vars : bool) (force_pr_var : bool) : tel =
    assert (not (no_pr_vars && force_pr_var));
    if !Flags.verbose then
      begin
        let vars_info = match no_pr_vars, force_pr_var with
          | true, false -> " (no pr vars)"
          | false, true -> " (force pr var)"
          | _ -> ""
        in
        print_string @@ String.make indent ' ' ^ "Inferring environment for " ^
                        hg#string_of_hterm hterm;
        begin
          match target with
          | Some target ->
            print_string @@ " : " ^ string_of_ty target;
          | None -> ()
        end;
        print_string @@ vars_info ^ "\n"
      end;
    let var_count = match env_data with
      | Left env -> env#var_count
      | Right var_count -> var_count
    in
    let res = match hterm with
      | HT a, [] ->
        if not force_pr_var && target |> option_map true (fun target ->
            TyList.exists (fun ty -> eq_ty target ty) (self#terminal_ity a)) then
          TargetEnvl.of_list_default_flags @@
          TyList.map (fun ty -> (ty, [empty_env var_count])) @@
          self#terminal_ity a
        else
          TargetEnvl.empty
      | HNT nt, [] ->
        if not force_pr_var && target |> option_map true (fun target ->
            self#nt_ty_exists nt target) then
          TargetEnvl.of_list_default_flags @@
          TyList.map (fun ty -> (ty, [empty_env var_count])) @@
          self#nt_ity nt
        else
          TargetEnvl.empty
      | HVar v, [] ->
        begin
          match target, env_data with
          | Some target, _ ->
            (* if target is known then either the type is inferred from it or correct environment
               is just type checked *)
            let env_if_var_ty_available v ty =
              let available = match env_data with
                | Left env -> env#mem v ty
                | Right _ -> true
              in
              if available then
                TargetEnvl.singleton target @@ singleton_env var_count v @@ sty ty
              else
                TargetEnvl.empty
            in
            if is_productive target then
              TargetEnvl.empty (* variables are only NP *)
            else if no_pr_vars then
              env_if_var_ty_available v target
            else if force_pr_var then
              let pr_target = with_productivity PR target in
              env_if_var_ty_available v pr_target
            else
              (* both NP and PR versions are possible *)
              let pr_target = with_productivity PR target in
              TargetEnvl.merge
                (env_if_var_ty_available v target) (env_if_var_ty_available v pr_target)
          | None, Left env ->
            (* if we're in this branch with None target then this must be a head variable or the
               whole term is a variable *)
            (* TODO maybe change definition of headvar to include var-only terms *)
            TargetEnvl.of_list_default_flags @@
            TyList.map (fun ty -> (ty, [singleton_env var_count v @@ sty ty])) @@
            env#get_var_ity v
          | None, Right _ -> failwith @@ "Type checking of terms with head variables or " ^
                                         "variable-only terms needs an environment"
        end
      | _ -> (* application *)
        let h, args = hg#decompose_hterm hterm in
        self#type_check_app h args target env_data no_pr_vars force_pr_var
    in
    if !Flags.verbose then
      begin
        print_string @@ String.make indent ' ' ^ hg#string_of_hterm hterm;
        if TargetEnvl.is_empty res then
          print_string " does not type check\n"
        else
          print_string @@ " type checks with the following targets and environments: " ^
                          TargetEnvl.to_string res ^
                          "\n"
      end;
    res

  method type_check_app (h : head) (args : hterm list) (target : ty option)
      (env_data : (env, int) either) (no_pr_vars : bool) (force_pr_var : bool) : tel =
    (* Definitions:
       * target is the type used in type checking hterm h : target and is either restricted to
         type in argument or all possible targets are computed
       * target argument's productivity is the productivity of an argument in target type
       * actual argument's productivity is computed productivity of the type of an argument and
         it does not have to be the same as productivity of the target argument
       * head's type is the type of h, where h is a variable, terminal, or nonterminal *)
    let h_arity = List.length args in
    (* Get all h typings *)
    let all_h_ity = self#infer_head_ity h env_data in
    (* filtering compatible head types assuming head is not a variable *)
    let h_ity = target |> option_map all_h_ity
                  (self#filter_compatible_heads all_h_ity h_arity)
    in
    if !Flags.verbose then
      begin
        print_string @@ String.make indent ' ' ^ "head_ity " ^ string_of_ity all_h_ity ^ "\n";
        print_string @@ String.make indent ' ' ^ "compatible head_ity " ^ string_of_ity h_ity ^
                        "\n"
      end;
    let h_ity = self#annotate_args args h_ity in
    let var_count = match env_data with
      | Left env -> env#var_count
      | Right var_count -> var_count
    in
    (* TODO optimizations:
       * caching argument index * argument required productivity -> envl
       * computing terms without variables first and short circuit after for all terms
       * computing terms with non-duplicating variables last with short-circuiting when
         duplication is expected
       * pre-computing order of computing argument types
       * maybe cache with versioning or just cache of all typings
       * flag to choose optimization in order to benchmark them later *)
    (* Iteration over each possible typing of the head *)
    List.fold_left TargetEnvl.merge TargetEnvl.empty @@
    (h_ity |> List.map (fun (args, h_target, head_pr) ->
         (* computing targets *)
         let pr_target, np_target = match target with
           | Some target ->
             if is_productive target then
               (Some target, None)
             else
               (None, Some target)
           | None ->
             if head_pr then
               (* TODO not possible to get np target with pr head?? *)
               (Some h_target, Some (with_productivity NP h_target))
             else
               (Some (with_productivity PR h_target), Some h_target)
         in
         (* construction of a TEL with no variables for each target *)
         let pr_start_tel =
           pr_target |> option_map TargetEnvl.empty (fun target ->
               TargetEnvl.singleton target @@ empty_env var_count
             )
         in
         let np_start_tel =
           np_target |> option_map TargetEnvl.empty (fun target ->
               TargetEnvl.singleton target @@ empty_env var_count
             )
         in
         let start_tel = TargetEnvl.merge pr_start_tel np_start_tel in
         if !Flags.verbose then
           begin
             print_string @@ String.make indent ' ' ^ "* Type checking ";
             print_string @@ String.concat " -> " @@ List.map (fun (arg_term, arg_ity) ->
                 "(" ^ hg#string_of_hterm arg_term ^ " : " ^ string_of_ity arg_ity ^ ")"
               ) args;
             if head_pr then
               print_string " -> ... -> pr\n"
             else
               print_string " -> ... -> np\n";
             indent <- indent + 2
           end;
         (* The target is args = (arg_i: arg_ity_i)_i and the codomain is head_pr.
            Iterate over arguments while intersecting variable environments with short-circuit.
            Note that below productive argument describes productivity of the argument term, not
            productivity of the argument in head's type.

            When the target is productive, there are three options:
            (1) head is productive and there are no restrictions on arguments, or
            (2) head is not productive and at least one argument is productive, or
            (3) head is not productive and all arguments are not productive and there
              is a duplication (which implies that at least two arguments are
              productive in head type assuming no head variables).

            (NP) When the target is not productive, the head is not productive, no
               arguments are productive, and there are no duplications. There still can
               be productive arguments in head's type, as long as that does not force a
               duplication. *)
         let tel = fold_left_short_circuit start_tel args TargetEnvl.empty
             (fun tel (arg_term, arg_ity) ->
                (* tel contains not only variable environments, but also information whether
                   there was a duplication (for (3) and (NP)) and whether a productive argument
                   was used (for (3)). *)
                TyList.fold_left_short_circuit tel arg_ity TargetEnvl.empty
                  (fun tel arg_ty ->
                     if !Flags.verbose then
                       begin
                         print_string @@ String.make indent ' ' ^ "* Typing argument " ^
                                         hg#string_of_hterm arg_term ^ " : " ^
                                         string_of_ity arg_ity ^ "\n";
                         indent <- indent + 2
                       end;
                     (* tel are possible variable environments constructed so far from previous
                        arguments, only for the current target.
                        When target argument is productive, the actual argument can be either
                        productive or not productive, but with a productive variable. When
                        target argument is not productive, the actual argument must be not
                        productive and have no productive variables. *)
                     let arg_tel =
                       if is_productive arg_ty then
                         (* case when target argument is productive *)
                         (* subcase when actual argument is productive *)
                         let pr_arg_tel =
                           (* productive actual argument implies productive target *)
                           match pr_target with
                           | Some pr_target ->
                             (* retarget also marks these environments with information that
                                productive actual argument was used and removes duplication
                                flags *)
                             (* TODO check if false flag for force_pr_var *)
                             TargetEnvl.retarget pr_target @@
                             self#type_check arg_term (Some arg_ty) env_data no_pr_vars false
                           | None -> TargetEnvl.empty
                         in
                         (* subcase when actual argument is nonproductive *)
                         let np_arg_tel =
                           if no_pr_vars then
                             TargetEnvl.empty
                           else
                             (* productive target argument together with not productive actual
                                argument implies productive variable *)
                             let arg_tel =
                               self#type_check arg_term (Some (with_productivity NP arg_ty))
                                 env_data false true
                             in
                             (* both target productivities are valid for nonproductive actual
                                argument *)
                             let pr_target_arg_tel = match pr_target with
                               | Some pr_target -> TargetEnvl.retarget pr_target arg_tel
                               | None -> TargetEnvl.empty
                             in
                             let np_target_arg_tel = match np_target with
                               | Some np_target -> TargetEnvl.retarget np_target arg_tel
                               | None -> TargetEnvl.empty
                             in
                             TargetEnvl.merge pr_target_arg_tel np_target_arg_tel
                         in
                         TargetEnvl.merge pr_arg_tel np_arg_tel
                       else
                         (* case when target argument is nonproductive *)
                         (* nonproductive target argument implies nonproductive actual argument
                            and no productive vars *)
                         let arg_tel =
                           self#type_check arg_term (Some arg_ty) env_data true false
                         in
                         (* both target productivities are valid for nonproductive target
                            argument *)
                         let pr_target_arg_tel = match pr_target with
                           | Some pr_target -> TargetEnvl.retarget pr_target arg_tel
                           | None -> TargetEnvl.empty
                         in
                         let np_target_arg_tel = match np_target with
                           | Some np_target -> TargetEnvl.retarget np_target arg_tel
                           | None -> TargetEnvl.empty
                         in
                         TargetEnvl.merge pr_target_arg_tel np_target_arg_tel
                     in
                     let intersection = TargetEnvl.intersect tel arg_tel in
                     if !Flags.verbose then
                       begin
                         indent <- indent - 2;
                         print_string @@ String.make indent ' ' ^
                                         "  env count for the argument: " ^
                                         string_of_int (TargetEnvl.size arg_tel) ^ "\n" ^
                                         String.make indent ' ' ^
                                         "  env count after intersection: " ^
                                         string_of_int (TargetEnvl.size intersection) ^ "\n"
                       end;
                     (* Productive target might require duplication in (3), but this can only
                        be checked at the end. (or TODO optimization in argument order).
                        Nonproductive target requires no duplication. *)
                     let res = TargetEnvl.filter_no_dup_for_np_targets intersection in
                     if !Flags.verbose then
                       print_string @@ String.make indent ' ' ^
                                       "  env count after no duplication filtering: " ^
                                       string_of_int (TargetEnvl.size res) ^ "\n";
                     res
                  )
             )
         in
         if !Flags.verbose then
           print_string @@ String.make indent ' ' ^
                           "* Intersected envs before duplication filtering:\n" ^
                           String.make (indent + 2) ' ' ^ TargetEnvl.to_string tel ^ "\n";
         let tel =
           if not head_pr then
             begin
               (* a duplication or productive actual argument is required when head is not
                  productive and target is productive *)
               let tel = TargetEnvl.filter_dup_or_pr_arg_for_pr_targets tel in
               if !Flags.verbose then
                 print_string @@ String.make indent ' ' ^
                                 "* env count after duplication or pr arg filtering: " ^
                                 string_of_int (TargetEnvl.size tel) ^ "\n";
               tel
             end
           else
             tel
         in
         if force_pr_var then
           let tel = TargetEnvl.filter_pr_vars tel in
           if !Flags.verbose then
             begin
               print_string @@ String.make indent ' ' ^ "* env count after pr var filtering: " ^
                               string_of_int (TargetEnvl.size tel) ^ "\n";
               indent <- indent - 2
             end;
           tel
         else
           begin
             indent <- indent - 2;
             tel
           end
       )
    )

  (* --- printing --- *)

  method print_nt_ity =
    print_string @@ "Types of nt:\n" ^
                    "============\n";
    for nt = 0 to hg#nt_count - 1 do
      print_string @@ hg#nt_name nt ^ ":\n";
      TyList.iter (fun ty ->
          print_string @@ string_of_ty ty ^ "\n"
        ) nt_ity.(nt)
    done

  method print_hterms_hty (should_be_printed : hterms_id -> bool) =
    print_string @@ "Types of hterms:\n" ^
                    "================\n";
    for id = 0 to hg#hterms_count - 1 do
      if should_be_printed id then
        begin
          print_string @@ string_of_int id ^ ":\n";
          let htys = hty_store#get_htys id in
          List.iter (fun hty ->
              print_string @@ String.concat "; " @@ List.map string_of_ity hty;
              print_string "\n"
            ) htys;
          print_string "\n"
        end
    done

  (* --- debugging --- *)

  method get_hty_store = hty_store
end
