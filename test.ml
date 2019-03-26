open Binding
open Environment
open Grammar
open GrammarCommon
open HGrammar
open HtyStore
open Main
open OUnit2
open TargetEnvListMap
open Type
open Typing
open Utilities

(* --- helper functions --- *)

let init_flags () =
  Flags.debugging := true;
  Flags.verbose := !Flags.debugging

let assert_equal_envls envl1 envl2 =
  assert_equal ~printer:EnvList.to_string ~cmp:EnvList.equal
    (EnvList.with_default_flags envl1) (EnvList.with_default_flags envl2)

let assert_equal_tels tel1 tel2 =
  assert_equal ~printer:TargetEnvl.to_string ~cmp:TargetEnvl.equal
    (TargetEnvl.with_default_flags tel1) (TargetEnvl.with_default_flags tel2)

let mk_grammar rules =
  let nonterminals = Array.mapi (fun i _ -> ("N" ^ string_of_int i, O)) rules in
  let g = new grammar nonterminals [||] rules in
  print_string @@ "Creating grammar:\n" ^
                  g#report_grammar;
  EtaExpansion.eta_expand g;
  g

let mk_hgrammar g =
  new HGrammar.hgrammar g

let mk_cfa hg =
  let cfa = new Cfa.cfa hg in
  cfa#expand;
  cfa#compute_dependencies;
  cfa

let mk_typing g =
  let hg = mk_hgrammar g in
  (hg, new Typing.typing hg)

let type_check_nt_wo_env (typing : typing) (hg : hgrammar) (nt : nt_id) (target : ty) =
  typing#type_check (hg#nt_body nt) (Some target) (Right (hg#nt_arity nt))

let type_check_nt_wo_env_wo_target (typing : typing) (hg : hgrammar) (nt : nt_id) =
  typing#type_check (hg#nt_body nt) None (Right (hg#nt_arity nt))

let senv hg nt i ity_str =
  singleton_env (hg#nt_arity nt) (nt, i) @@ ity_of_string ity_str

let list_sort_eq (l1 : 'a list list) (l2 : 'a list list) : bool =
  (List.sort (compare_lists Pervasives.compare) l1) =
  (List.sort (compare_lists Pervasives.compare) l2)

let string_of_ll = string_of_list (string_of_list string_of_int)

(* --- tests --- *)

let utilities_test () : test =
  "utilities" >::: [
    "product-0" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [] @@
        product []
      );
    
    "product-1" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [[1]] @@
        product [[1]]
      );
    
    "product-2" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [[1; 2]] @@
        product [[1]; [2]]
      );
    
    "product-3" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [
            [1; 2; 3];
            [1; 2; 33];
            [1; 2; 333];
            [11; 2; 3];
            [11; 2; 33];
            [11; 2; 333]
          ] @@
        product [[1; 11]; [2]; [3; 33; 333]]
      );

    "product-4" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [
            [1; 2];
            [1; 22]
          ] @@
        product [[1]; [2; 22]]
      );

    "product-5" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [[1]; [2]] @@
        product [[1; 2]]
      );
    
    "product_with_one_fixed-0" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [] @@
        product_with_one_fixed [] []
      );
    
    "product_with_one_fixed-1" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [[0]] @@
        product_with_one_fixed [[1; 2; 3]] [0]
      );
    
    "product_with_one_fixed-2" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [
            [0; 0];
            [0; 2];
            [0; 22];
            [1; 0];
            [11; 0]
          ] @@
        product_with_one_fixed [[1; 11]; [2; 22]] [0; 0]
      );
    
    "product_with_one_fixed-3" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [
            [0; 0; 0];
            [1; 0; 0];
            [0; 2; 0];
            [0; 0; 3];
            [0; 22; 0];
            [0; 222; 0];
            [1; 2; 0];
            [1; 0; 3];
            [1; 22; 0];
            [1; 222; 0];
            [0; 2; 3];
            [0; 22; 3];
            [0; 222; 3]
          ] @@
        product_with_one_fixed [[1]; [2; 22; 222]; [3]] [0; 0; 0]
      );
    
    "product_with_one_fixed-4" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [
            [0; 0; 0; 0];
            [1; 0; 0; 0];
            [0; 2; 0; 0];
            [0; 0; 3; 0];
            [0; 0; 0; 4];
            [1; 2; 0; 0];
            [1; 0; 3; 0];
            [1; 0; 0; 4];
            [0; 2; 3; 0];
            [0; 2; 0; 4];
            [0; 0; 3; 4];
            [0; 2; 3; 4];
            [1; 0; 3; 4];
            [1; 2; 0; 4];
            [1; 2; 3; 0]
          ] @@
        product_with_one_fixed [[1]; [2]; [3]; [4]] [0; 0; 0; 0]
      );
  ]

let conversion_test () : test =
  (* These preterminals are defined in a way so that they should be converted to respective
     terminals from paper without creating additional terms (such as functions). *)
  let preserved_preterminals = [
    Syntax.Terminal ("a", 1, true);
    Syntax.Terminal ("b", 2, false);
    Syntax.Terminal ("e", 0, false);
    Syntax.Terminal ("id", 1, false)
  ] in
  (* This grammar aims to test all combinations of applications of terminals a, b, e with
     all possible numbers of applied arguments. It also tests that not counted terminal
     with one child is removed when it has an argument (as it is identity). And it also
     tests built-in br terminal. *)
  let test_prerules = [
    ("E", [], Syntax.PApp (Syntax.Name "e", []));
    ("A", ["x"], Syntax.PApp (Syntax.Name "a", [
         Syntax.PApp (Syntax.Name "x", [])
       ]));
    ("B", [], Syntax.PApp (Syntax.Name "b", []));
    ("Be", [], Syntax.PApp (Syntax.Name "b", [
         Syntax.PApp (Syntax.Name "e", [])
       ]));
    ("BAee", [], Syntax.PApp (Syntax.Name "b", [
         Syntax.PApp (Syntax.Name "a", [Syntax.PApp (Syntax.Name "e", [])]);
         Syntax.PApp (Syntax.Name "e", [])
       ]));
    ("X", ["x"], Syntax.PApp (Syntax.Name "x", [
         Syntax.PApp (Syntax.Name "e", [])
       ]));
    ("Xa", [], Syntax.PApp (Syntax.NT "X", [
         Syntax.PApp (Syntax.Name "a", [])
       ]));
    ("IDe", [], Syntax.PApp (Syntax.Name "id", [
         Syntax.PApp (Syntax.Name "e", [])
       ]));
    ("ID", [], Syntax.PApp (Syntax.Name "id", []));
    ("BR", [], Syntax.PApp (Syntax.Name "br", []));
    ("BRe", [], Syntax.PApp (Syntax.Name "br", [
         Syntax.PApp (Syntax.Name "e", [])
       ]));
    ("BRxy", ["x"; "y"], Syntax.PApp (Syntax.Name "br", [
         Syntax.PApp (Syntax.Name "x", []);
         Syntax.PApp (Syntax.Name "y", [])
       ]))
  ] in
  let gram = Conversion.prerules2gram (test_prerules, preserved_preterminals) in
  if !Flags.debugging then
    print_string @@ "Conversion test grammar:\n" ^ gram#report_grammar ^ "\n";
  "conversion" >::: [
    (* Terminals
       a -> 1 $.
       b -> 2.
       e -> 0.
       should be preserved as in the paper, without needless conversion. Therefore, there
       should be no functions apart from the one from identity without arguments, i.e.,
       exactly one extra rule. *)
    "prerules2gram-1" >:: (fun _ ->
        assert_equal ~printer:string_of_int 13 @@
        Array.length gram#rules
      );

    (* Checking that number of leaf terms is correct - nothing extra was added or removed
       aside from extra rule from identity without arguments. *)
    "prerules2gram-2" >:: (fun _ ->
        assert_equal ~printer:string_of_int 23
        gram#size
      );
  ]

let type_test () : test =
  "type" >::: [
    "string_of_ty-1" >:: (fun _ ->
        assert_equal "pr" @@ string_of_ty PR
      );

    "string_of_ty-2" >:: (fun _ ->
        assert_equal "np -> pr" @@
        string_of_ty (mk_fun (sty NP) PR)
      );

    "string_of_ty-3" >:: (fun _ ->
        assert_equal "(np -> pr) -> np" @@
        string_of_ty (mk_fun (sty (mk_fun (sty NP) PR)) NP)
      );

    "string_of_ty-4" >:: (fun _ ->
        assert_equal "pr /\\ np -> pr" @@
        string_of_ty (mk_fun (TyList.of_list [PR; NP]) PR)
      );

    "string_of_ty-5" >:: (fun _ ->
        assert_equal "T -> pr" @@ string_of_ty (mk_fun (TyList.empty) PR)
      );

    "string_of_ty-6" >:: (fun _ ->
        assert_equal "(pr -> pr) -> (np -> pr) -> np -> pr" @@
        string_of_ty
          (mk_fun
             (sty (mk_fun (sty PR) PR))
             (mk_fun
                (sty (mk_fun (sty NP) PR))
                (mk_fun (sty NP) PR)))
      );

    "string_of_ity-1" >:: (fun _ ->
        assert_equal "(pr -> pr) /\\ (np -> np)" @@
        string_of_ity (TyList.of_list [mk_fun (sty PR) PR; mk_fun (sty NP) NP])
      );
    
    "ty_of_string-1" >:: (fun _ ->
        assert_equal ~cmp:Ty.equal PR @@ ty_of_string "pr"
      );

    "ty_of_string-2" >:: (fun _ ->
        assert_equal ~cmp:Ty.equal (mk_fun (sty NP) PR) @@ ty_of_string "np -> pr"
      );

    "ty_of_string-3" >:: (fun _ ->
        assert_equal ~cmp:Ty.equal (mk_fun (sty (mk_fun (sty NP) PR)) NP) @@
        ty_of_string "(np -> pr) -> np"
      );

    "ty_of_string-4" >:: (fun _ ->
        assert_equal ~cmp:Ty.equal (mk_fun (TyList.of_list [PR; NP]) PR) @@
        ty_of_string "pr /\\ np -> pr"
      );

    "ty_of_string-5" >:: (fun _ ->
        assert_equal ~cmp:Ty.equal (mk_fun (TyList.empty) PR) @@
        ty_of_string "T -> pr"
      );

    "ty_of_string-6" >:: (fun _ ->
        assert_equal ~cmp:Ty.equal
          (mk_fun
             (sty (mk_fun (sty PR) PR))
             (mk_fun
                (sty (mk_fun (sty NP) PR))
                (mk_fun (sty NP) PR))) @@
        ty_of_string "(pr -> pr) -> (np -> pr) -> np -> pr"
      );

    "ity_of_string-1" >:: (fun _ ->
        assert_equal ~cmp:TyList.equal
          (TyList.of_list [mk_fun (sty PR) PR; mk_fun (sty NP) NP]) @@
        ity_of_string "(pr -> pr) /\\ (np -> np)"
      );
  ]

(** The smallest possible grammar. *)
let grammar_e () = mk_grammar
    [|
      (0, T E) (* N0 -> e *)
    |]

let typing_e_test () =
  let hg, typing = mk_typing @@ grammar_e () in
  [
    (* checking if matching arguments to their types works *)
    "annotate_args" >:: (fun _ ->
        assert_equal
          [
            ([(1, TyList.singleton NP); (2, TyList.singleton PR)], Fun (4, TyList.empty, PR), true)
          ]
          (typing#annotate_args
             [1; 2]
             (TyList.singleton
                (Fun (2, TyList.singleton NP,
                      Fun (3, TyList.singleton PR,
                           Fun (4, TyList.empty, PR)
                          )
                     )
                )
             )
          )
      );
    
    (* check if e : np type checks *)
    "type_check-1" >:: (fun _ ->
        assert_equal_tels
          (TargetEnvl.singleton NP @@ empty_env @@ hg#nt_arity 0)
          (type_check_nt_wo_env typing hg 0 NP false false)
      );

    (* checking basic functionality of forcing pr vars *)
    "type_check-2" >:: (fun _ ->
        assert_equal_tels
          TargetEnvl.empty
          (type_check_nt_wo_env typing hg 0 NP false true)
      );

    (* checking that forcing no pr vars does not break anything when there are only terminals *)
    "type_check-3" >:: (fun _ ->
        assert_equal_tels
          (TargetEnvl.singleton NP @@ empty_env @@ hg#nt_arity 0)
          (type_check_nt_wo_env typing hg 0 NP true false)
      );
  ]

(** Grammar that tests usage of a variable. *)
let grammar_ax () = mk_grammar
    [|
      (0, App (NT 1, T E)); (* N0 -> N1 e *)
      (1, App (T A, Var (1, 0))) (* N1 x -> a x *)
    |]

let typing_ax_test () =
  let hg, typing = mk_typing @@ grammar_ax () in
  [
    (* check that a x : pr accepts both productivities of x *)
    "type_check-4" >:: (fun _ ->
        assert_equal_tels
          (TargetEnvl.of_list_default_flags
           [
             (PR, [
                senv hg 1 0 "pr";
                senv hg 1 0 "np"
              ])
           ])
          (type_check_nt_wo_env typing hg 1 PR false false)
      );

    (* check that a x : np does not type check *)
    "type_check-5" >:: (fun _ ->
        assert_equal_tels
          TargetEnvl.empty
          (type_check_nt_wo_env typing hg 1 NP false false)
      );
  ]
  
(** Grammar that tests intersection - x and y are inferred from one argument in N1 rule, and y and
    z from the other. N4 tests top. *)
let grammar_xyyz () = mk_grammar
    [|
      (* N0 -> N1 a N4 e *)
      (0, App (App (App (NT 1, T A), NT 4), T E));
      (* N1 x y z -> N2 x y (N3 y z) *)
      (3, App (
          App (App (NT 2, Var (1, 0)), Var (1, 1)),
          App (App (NT 3, Var (1, 1)), Var (1, 2))
        ));
      (* N2 x y v -> x (y v) *)
      (3, App (Var (2, 0), App (Var (2, 1), Var (2, 2))));
      (* N3 y z -> y z *)
      (2, App (Var (3, 0), Var (3, 1)));
      (* N4 x -> b (a x) x *)
      (1, App (App (T B, App (T A, Var (4, 0))), Var (4, 0)));
      (* N5 -> N5 *)
      (0, NT 5)
    |]

let typing_xyyz_test () =
  let hg, typing = mk_typing @@ grammar_xyyz () in
  ignore @@ typing#add_nt_ty 2 @@ ty_of_string "(pr -> pr) -> (np -> pr) -> np -> pr";
  ignore @@ typing#add_nt_ty 3 @@ ty_of_string "(np -> np) -> np -> np";
  let id0_0 = hg#locate_hterms_id 0 [0] in
  ignore @@ typing#get_hty_store#add_hty id0_0
    [
      ity_of_string "pr -> pr";
      ity_of_string "np -> np";
      ity_of_string "np -> pr"
    ];
  ignore @@ typing#get_hty_store#add_hty id0_0
    [
      ity_of_string "pr -> pr";
      ity_of_string "pr -> pr";
      ity_of_string "pr -> pr"
    ];
  [
    (* check that intersection of common types from different arguments works *)
    "type_check-6" >:: (fun _ ->
        assert_equal_tels
          (TargetEnvl.singleton PR @@
           new env [|
             ity_of_string "pr -> pr";
             ity_of_string "(np -> pr) /\\ (np -> np)";
             ity_of_string "np"
           |]) @@
        type_check_nt_wo_env typing hg 1 PR false false
      );

    (* check that branching works *)
    "type_check-7" >:: (fun _ ->
        assert_equal_tels
          (TargetEnvl.of_list_default_flags [
              (PR, [
                 senv hg 4 0 "pr";
                 senv hg 4 0 "np"
               ])
            ]) @@
        type_check_nt_wo_env typing hg 4 PR false false
      );

    (* check that branching works *)
    "type_check-8" >:: (fun _ ->
        assert_equal_tels
          (TargetEnvl.of_list_default_flags [
              (NP, [
                 senv hg 4 0 "pr";
                 senv hg 4 0 "np"
               ])
            ]) @@
        type_check_nt_wo_env typing hg 4 NP false false
      );

    (* Basic creation of bindings without a product *)
    "binding2envl-1" >:: (fun _ ->
        assert_equal_envls
          (EnvList.of_list_default_flags [
              new env @@ [|
                ity_of_string "pr -> pr";
                ity_of_string "pr -> pr";
                ity_of_string "pr -> pr"
              |];
              new env @@ [|
                ity_of_string "pr -> pr";
                ity_of_string "np -> np";
                ity_of_string "np -> pr"
              |]
            ]) @@
        typing#binding2envl (hg#hterm_arity id0_0) None None [(0, 0, id0_0)]
      );

    (* Basic creation of bindings with filtered out all but first variables, without product *)
    "binding2envl-2" >:: (fun _ ->
        assert_equal_envls
          (EnvList.of_list_default_flags [
              new env @@ [|
                ity_of_string "pr -> pr";
                ity_of_string "T";
                ity_of_string "T"
              |]
            ]) @@
        typing#binding2envl (hg#hterm_arity id0_0) (Some (SortedVars.of_list [(0, 0)])) None
          [(0, 0, id0_0)]
      );

    (* Creation of bindings with filtering and fixed hty of hterms. *)
    "binding2envl-3" >:: (fun _ ->
        assert_equal_envls
          (EnvList.of_list_default_flags [
              new env @@ [|
                ity_of_string "np -> pr";
                ity_of_string "T";
                ity_of_string "T"
              |]
            ]) @@
        typing#binding2envl (hg#hterm_arity id0_0) (Some (SortedVars.of_list [(0, 0)]))
          (Some (id0_0, [ity_of_string "np -> pr"; ity_of_string "pr"; ity_of_string "np"]))
          [(0, 0, id0_0)]
      );

    (* Creation of bindings with filtering and filtered out fixed hty of hterms. *)
    (* TODO but need two hterms in binding for that *)
  ]

(** Grammar that tests typing with duplication in N1 when N2 receives two the same arguments. It
    also tests no duplication when these arguments are different in N3. It also has a binding where
    N4 is partially applied, so it has two elements from two different nonterminals. *)
let grammar_dup () = mk_grammar
    [|
      (* N0 -> b (b (N1 a) (N3 a a)) (N5 N4 (a e)) *)
      (0, App (App (
           T B,
           App (App (
               T B,
               App (NT 2, T A)),
                App (App (NT 3, T A), App (T A, T E)))),
               App (App (NT 5, NT 4), App (T A, T E))));
      (* N1 x y z -> x (y z) *)
      (3, App (Var (1, 0), App  (Var (1, 1), Var (1, 2))));
      (* N2 x -> N1 x x (a e) *)
      (1, App (App (App (NT 1, Var (2, 0)), Var (2, 0)), App (T A, T E)));
      (* N3 x y -> N1 x x y *)
      (2, App (App (App (NT 1, Var (3, 0)), Var (3, 0)), Var (3, 1)));
      (* N4 x y z -> N1 x y z *)
      (3, App (App (App (NT 1, Var (4, 0)), Var (4, 1)), Var (4, 2)));
      (* N5 x -> N6 (x a) *)
      (1, App (NT 6, App (Var (5, 0), T A)));
      (* N6 x -> x a *)
      (1, App (Var (6, 0), T A))
    |]

let typing_dup_test () =
  let hg, typing = mk_typing @@ grammar_dup () in
  ignore @@ typing#add_nt_ty 1 @@ ty_of_string  "(pr -> pr) -> (pr -> pr) -> pr -> np";
  ignore @@ typing#add_nt_ty 1 @@ ty_of_string  "(pr -> np) -> (pr -> np) -> pr -> np";
  [
    (* All valid typings of x type check, because the application is already productive due to
       a e being productive. *)
    "type_check-9" >:: (fun _ ->
        assert_equal_tels
          (TargetEnvl.of_list_default_flags [
              (PR, [
                 senv hg 2 0 "pr -> pr";
                 senv hg 2 0 "pr -> np"
               ])
            ])
          (type_check_nt_wo_env typing hg 2 PR false false)
      );

    (* No valid environment, because a e is productive and makes the application with it as
       argument productive. *)
    "type_check-10" >:: (fun _ ->
        assert_equal_tels
          TargetEnvl.empty
          (type_check_nt_wo_env typing hg 2 NP false false)
      );

    (* Only one valid env when there is a duplication. Since everything in N1 is a variable,
       there is no way to create pr terms without a duplication. The x : pr -> pr typing
       causes a duplication and type checks. Typing x : pr -> np does not type check, because
       it is not productive, so it is not a duplication. y : pr is forced by there being no
       known typing of the head with unproductive last argument. *)
    "type_check-11" >:: (fun _ ->
        assert_equal_tels
          (TargetEnvl.singleton PR @@ new env [|
              ity_of_string "pr -> pr";
              ity_of_string "pr"
            |])
          (type_check_nt_wo_env typing hg 3 PR false false)
      );

    (* Only one valid env when there is no duplication. This is exactly the opposite of the test
       above with x : pr -> np passing and x : pr -> pr failing and y : pr being forced. *)
    "type_check-12" >:: (fun _ ->
        assert_equal_tels
          (TargetEnvl.singleton NP @@ new env [|
              ity_of_string "pr -> np";
              ity_of_string "pr"
            |])
          (type_check_nt_wo_env typing hg 3 NP false false)
      );

    (* Similar to test 11, but this time there are separate variables used for first
       and second argument, so there is no place for duplication. This means that there is no
       way to achieve productivity. *)
    "type_check-13" >:: (fun _ ->
        assert_equal_tels
          TargetEnvl.empty
          (type_check_nt_wo_env typing hg 4 PR false false)
      );

    (* Similar to test 12, but this time the duplication cannot happen. *)
    "type_check-14" >:: (fun _ ->
        assert_equal_tels
          (TargetEnvl.of_list_default_flags @@ [
              (NP, [
                  new env [|
                    ity_of_string "pr -> pr";
                    ity_of_string "pr -> pr";
                    ity_of_string "pr"
                  |];
                  new env [|
                    ity_of_string "pr -> np";
                    ity_of_string "pr -> np";
                    ity_of_string "pr"
                  |]
                ])
            ]
          )
          (type_check_nt_wo_env typing hg 4 NP false false)
      );

    (* Typing without target *)
    "type_check-15" >:: (fun _ ->
        assert_equal_tels
          (TargetEnvl.of_list_default_flags @@ [
              (PR, [
                  new env [|
                    ity_of_string "pr -> pr";
                    ity_of_string "pr"
                  |]
                ]);
              (NP, [
                  new env [|
                    ity_of_string "pr -> np";
                    ity_of_string "pr"
                  |]
                ])
            ]
          )
          (type_check_nt_wo_env_wo_target typing hg 3 false false)
      );
  ]

let typing_test () : test =
  init_flags ();
  "typing" >:::
  typing_e_test () @
  typing_ax_test () @
  typing_xyyz_test () @
  typing_dup_test ()

let cfa_test () : test =
  init_flags ();
  let hg_xyyz = mk_hgrammar @@ grammar_xyyz () in
  let cfa_xyyz = mk_cfa hg_xyyz in
  let hg_dup = mk_hgrammar @@ grammar_dup () in
  let cfa_dup = mk_cfa hg_dup in
  "cfa" >:::
  [
    (* empty binding with no variables *)
    "nt_binding-1" >:: (fun _ ->
        assert_equal
          [[]]
          (cfa_xyyz#lookup_nt_bindings 0)
      );

    (* single binding, directly *)
    "nt_binding-2" >:: (fun _ ->
        assert_equal
          [
            [(0, 2, List.hd @@ snd @@ hg_xyyz#nt_body 0)]
          ]
          (cfa_xyyz#lookup_nt_bindings 1)
      );

    (* two bindings, both indirectly due to partial application *)
    "nt_binding-3" >:: (fun _ ->
        assert_equal
          [
            "[nt2v2]";
            "[nt3v1]"
          ]
          (List.sort Pervasives.compare @@ List.map (fun binding ->
               match binding with
               | [(_, _, id)] -> hg_xyyz#string_of_hterms id
               | _ -> failwith "fail"
             ) @@ cfa_xyyz#lookup_nt_bindings 4)
      );

    (* no bindings when unreachable *)
    "nt_binding-4" >:: (fun _ ->
        assert_equal
          []
          (cfa_xyyz#lookup_nt_bindings 5)
      );

    (* binding with args from different nonterminals *)
    "nt_binding-5" >:: (fun _ ->
        assert_equal
          [
            [
              (* a in N5 *)
              (0, 0, hg_dup#locate_hterms_id 5 [0; 0; 0]);
              (* a <var> in N6 *)
              (1, 2, hg_dup#locate_hterms_id 6 [0])
            ]
          ]
          (cfa_dup#lookup_nt_bindings 4)
      );

    (* checking that cfa detected that in N0 nonterminal N1 was applied to N4 *)
    "var_binding-1" >:: (fun _ ->
        assert_equal
          [
            (HNT 4, [])
          ]
          (cfa_xyyz#lookup_binding_var (1, 1))
      );
  ]  

let examples_test () : test =
  init_flags ();
  let filenames_in_dir = List.filter (fun f -> String.length f > 8)
      (Array.to_list (Sys.readdir "examples")) in
  let inf_filenames = List.filter (fun f ->
      String.sub f (String.length f - 8) 8 = "_inf.inf") filenames_in_dir in
  let fin_filenames = List.filter (fun f ->
      String.sub f (String.length f - 8) 8 = "_fin.inf") filenames_in_dir in
  let path filename = Some (String.concat "" ["examples/"; filename]) in
  "Examples" >::: [
    "Infinite examples" >::: List.map (fun filename ->
        filename >:: (fun _ ->
            assert_equal (Main.parse_and_report_finiteness (path filename)) false))
      inf_filenames;
    "Finite examples" >::: List.map (fun filename ->
        filename >:: (fun _ ->
            assert_equal (Main.parse_and_report_finiteness (path filename)) true))
      fin_filenames]

let tests () = [
  utilities_test ();
  conversion_test ();
  cfa_test ();
  type_test ();
  typing_test ();
  (* examples_test () *)
]
