
open Timing
open Utilities

let report_usage () =
  print_string @@ "Usage: \n" ^
                  "infsat <option>* <filename> \n\n" ^
                  " -d\n" ^
                  "  debug mode\n"

let program_info = "InfSat 0.1: Saturation-based finiteness checker for higher-order " ^
                   "recursion schemes"

let options = [
  ("-q", Arg.Set Flags.quiet, "Enables quiet mode and exits with code 0 for infinite " ^
                              "language, 1 for finite, 2 for maybe finite (with unsafe terms) " ^
                              "and something else on error");
  ("-f", Arg.Set Flags.force_unsafe, "Skip term safety check");
  ("-v", Arg.Set Flags.verbose_main, "Enables basic verbosity");
  ("-vv", Arg.Set Flags.verbose_all, "Enables full verbosity");
  ("-vprep", Arg.Set Flags.verbose_preprocessing, "Enables verbose parsing and preprocessing");
  ("-vproof", Arg.Set Flags.verbose_proofs, "Enables verbose proofs");
  ("-vtype", Arg.Set Flags.verbose_typing, "Enables verbose typing results");
  ("-vsat", Arg.Set Flags.verbose_queues, "Enables verbose saturation tasks");
  ("-vprof", Arg.Set Flags.verbose_profiling, "Enables verbose profiling");
  ("-maxiters", Arg.Set_int Flags.maxiters,
   "Maximum number of saturation iterations before giving up");
  ("-tf", Arg.Symbol (
      ["full"; "shortened"; "short"],
      fun f -> Flags.type_format := f
    ),
   "Format in which types will be printed. \"full\" for " ^
   "(pr, (np, (pr, o) -> o) -> (np, o) -> o), \"shortened\" for " ^
   "(pr, (np, pr -> o) -> np -> o), or \"short\" for (pr -> np) -> np -> pr. " ^
   "Default is \"full\".");
]

(** Parses a file to HORS prerules and automata definition. *)
let parse_file filename =
  let in_strm = 
    try
      open_in filename 
    with
      Sys_error _ ->
      failwith @@ "Cannot open file: " ^ filename ^ "."
  in
  print_verbose (not !Flags.quiet) @@ lazy (
    "Analyzing " ^ filename ^ "."
  );
  let lexbuf = Lexing.from_channel in_strm in
  let result =
    try
      InfSatParser.main InfSatLexer.token lexbuf
    with 
    | Failure _ ->
      failwith "Lexical error."
    | Parsing.Parse_error ->
      failwith "Parse error."
  in
  let _ = 
    try
      close_in in_strm
    with
    | Sys_error _ ->
      failwith @@ "Cannot close file " ^ filename
  in
    result

(** Parses stdin to HORS prerules and automata transitions. *)
let parse_stdin () =
  print_verbose (not !Flags.quiet) @@ lazy "Reading standard input until EOF...";
  let in_strm = stdin in
  let lexbuf = Lexing.from_channel in_strm in
  let result =
    try
      InfSatParser.main InfSatLexer.token lexbuf
    with 
    | Failure _ ->
      failwith "Lexical error"
    | Parsing.Parse_error ->
      failwith "Parse error"
  in
    result

let string_of_input (prerules, tr) =
  Syntax.string_of_prerules prerules ^ "\n" ^ Syntax.string_of_preterminals tr

(** Main part of InfSat. Takes parsed input, returns whether the paths generated by HORS contain
    uniformly bounded number of counted letters. *)
let report_finiteness (input : Syntax.prerules * Syntax.preterminals) : Saturation.infsat_result =
  let grammar = time "conversion" (fun () -> Conversion.prerules2gram input) in
  time "eta-expansion" (fun () -> EtaExpansion.eta_expand grammar);
  let hgrammar = time "head conversion" (fun () -> new HGrammar.hgrammar grammar) in
  print_verbose (not !Flags.quiet) @@ lazy (
    "Rewritten input grammar:\n\n" ^
    hgrammar#to_string ^ "\n"
  );
  let safety_error = Safety.check_safety hgrammar in
  begin
    match safety_error with
    | Some error ->
      print_verbose (not !Flags.quiet) @@ lazy (
        "The grammar contains unsafe terms:\n" ^
        error ^ "\n"
      )
    | None -> ()
  end;
  let cfa = time "0CFA" (fun () ->
      let cfa = new Cfa.cfa hgrammar in
      cfa#expand;
      cfa#compute_dependencies;
      cfa)
  in
  time "saturation" (fun () ->
      let saturation = new Saturation.saturation hgrammar cfa in
      saturation#saturate safety_error
    )

(** Parses given file or stdin and returns whether the HORS is finite. *)
let parse_and_report_finiteness (filename : string option) : Saturation.infsat_result =
  let input = time "parsing" (fun () ->
      try
        match filename with
        | Some f -> parse_file f
        | None -> parse_stdin ()
      with
      | InfSatLexer.LexError s -> failwith @@ "Lexer error: " ^ s
    )
  in
  print_verbose !Flags.verbose_preprocessing @@ lazy (
    "Input:\n\n" ^ string_of_input input
  );
  report_finiteness input
  
let main () : unit =
  try
    let filenames = ref [] in
    program_info |> Arg.parse options (fun filename ->
        filenames := filename :: !filenames
      );
    let filename = match !filenames with
      | [] -> None
      | [f] -> Some f
      | _ -> failwith "Expected at most one filename."
    in
    Flags.propagate_flags ();
    let start_t = Sys.time () in
    let res = parse_and_report_finiteness filename in
    let end_t = Sys.time () in
    report_timings start_t end_t;
    (* return value indicates finiteness only when return flag is on *)
    match res with
    | Infinite _ -> exit 0
    | Finite ->
      if !Flags.quiet then
        exit 1
      else
        exit 0
    | Unknown ->
      exit 2
  with
  | Failure msg ->
    prerr_endline msg;
    exit (-1)
