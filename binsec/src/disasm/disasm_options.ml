(**************************************************************************)
(*  This file is part of BINSEC.                                          *)
(*                                                                        *)
(*  Copyright (C) 2016-2018                                               *)
(*    CEA (Commissariat à l'énergie atomique et aux énergies              *)
(*         alternatives)                                                  *)
(*                                                                        *)
(*  you can redistribute it and/or modify it under the terms of the GNU   *)
(*  Lesser General Public License as published by the Free Software       *)
(*  Foundation, version 2.1.                                              *)
(*                                                                        *)
(*  It is distributed in the hope that it will be useful,                 *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of        *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *)
(*  GNU Lesser General Public License for more details.                   *)
(*                                                                        *)
(*  See the GNU Lesser General Public License version 2.1                 *)
(*  for more details (enclosed in the file licenses/LGPLv2.1).            *)
(*                                                                        *)
(**************************************************************************)


(* let simplification_levels = ["prog";"fun";"seq";"fun-no-inline";
 *                              "seq-no-inline";"fun-no-sum";
 *                              "seq-no-sum"]
 *
 * let simpl_fun = ref false
 * let simpl_sequence = ref false
 * let simpl_inline_calls = ref true
 * let simpl_no_summaries = ref false
 * let simpl = ref false
 *
 *
 * let simplification_cli_handler =
 *   Arg.Symbol (
 *       simplification_levels,
 *       (fun s ->
 *         match (String.lowercase_ascii s) with
 *         | "prog" -> simpl :=  true
 *         | "fun" -> simpl := true; simpl_fun := true
 *         | "seq" -> simpl := true; simpl_sequence := true
 *         | "fun-no-inline" ->
 *            simpl := true;
 *            simpl_fun := true;
 *            simpl_inline_calls := false
 *         | "seq-no-inline" ->
 *            simpl := true;
 *            simpl_sequence := true;
 *            simpl_inline_calls := false
 *         | "fun-no-sum" ->
 *            simpl := true;
 *            simpl_fun := true;
 *            simpl_no_summaries := true
 *         | "seq-no-sum" ->
 *            simpl := true;
 *            simpl_sequence := true;
 *            simpl_no_summaries := true
 *         | _ ->
 *            assert false)
 *     ) *)


include Cli.Make(
struct
  let name = "disassembly"
  let shortname = "disasm"
end
)

type disassembly_mode =
  | Recursive | Linear | Linear_byte_wise | Extended_linear

module Disassembly_mode = struct
  include Builder.Variant_choice_assoc(
  struct
  type t = disassembly_mode

  let assoc_map = [
    "rec", Recursive;
    "linear", Linear;
    "bytelinear", Linear_byte_wise;
    "extlinear", Extended_linear;
  ]

  let default = Linear
  let name = "mode"
  let doc = " Set disassembly mode"
  end)
end


type specifics =
  | All
  | NoInline
  | NoSummaries

type simplification =
  | No_simplification
  | Program
  | Function of specifics
  | Sequence of specifics

module Simplification = Builder.Variant_choice_assoc(
struct
  type t = simplification

  let assoc_map = [
      "prog", Program;
      "fun", Function All;
      "seq", Sequence All;
      "fun-no-inline", Function NoInline;
      "seq-no-inline", Function NoInline;
      "fun-no-sum", Function NoSummaries;
      "seq-no-sum", Function NoSummaries;
      "none", No_simplification;
    ]

  let default = No_simplification
  let name = "simplify"
  let doc = " Activate DBA simplification on given level"
end
)

module DbaOutputFile = struct
  include Builder.String(
    struct
      let name = "o-dba"
      let default = "out.dba"
      let doc = Format.sprintf " Set DBA instructions output file [%s]" default
    end)
end


module OpcodeOutputFile =
  Builder.String_option(
  struct
    let name = "dump"
    let doc = " Set opcodes output file [stdout]"
  end)


module NoLoaderMode =
  Builder.False(
  struct
    let name = "no-loader"
    let doc = "Do not use loader and start at 0x0"
  end
  )

module IgnoreUnhandledInstructions =
  Builder.True (
  struct
    let name = "ignore-unhandled"
    let doc = "Skip unknown instructions"
  end
  )

module ProtectedMode = Builder.False (
  struct
    let name = "protected-mode"
    let doc =
      "Activate protected mode memory addressing (using segment selectors)"
  end
  )

module ShowInstructionCount =
  Builder.False (
  struct
    let name = "show-instruction-count"
    let doc = "Show a summary of encountered instructions"
  end
  )

module Sections =
  Builder.String_set (
  struct
    let name = "sections"
    let doc = "Disassemble given comma separated list of sections"
  end
  )

module Functions =
  Builder.String_set (
  struct
    let name = "functions"
    let doc = "Disassemble given comma separated list of functions"
  end
  )

module HandleSegments =
  Builder.String_set(
  struct
    let name = "handle-seg"
    let doc = "Activate set of segments"
  end
  )

module SimplifiedDisassembly =
  Builder.False
    (struct
      let name = "no-hunk-simplification"
      let doc  = "Disable DBA hunks simplifications"
    end
    )


module Decode_instruction =
  Builder.String_option(struct
      let name = "decode"
      let doc = "Decode hexadecimal opcode"
    end);;



module Decode_replacement =
  (* Note: we use any instead of a list, because we ',' in the dba
     could be wrongly interpreted by the Cli. *)
  Builder.Any(struct
    let name = "decode-replacement"
    let doc = "Replace instructions with a specific dba blocks. Syntax: (0xaddress -> dhunk)*"
    type t = Dhunk.t Virtual_address.Map.t
    let to_string x =
      if Virtual_address.Map.is_empty x then "no substitution" else
        Virtual_address.Map.fold (fun addr dhunk acc ->
            acc ^ (Format.asprintf "0x%a -> %a\n" Virtual_address.pp addr Dhunk.pp dhunk)
          ) x ""
    ;;
    let default = Virtual_address.Map.empty
    let of_string s =
      let l = Parser.dhunk_substitutions_eof Lexer.token @@ Lexing.from_string s in
      let map = List.fold_left (fun acc (addr,dhunk) ->
          Virtual_address.Map.add addr dhunk acc
        ) Virtual_address.Map.empty l
      in
      Logger.debug "parsed replacements\n%s" (to_string map);
      map
    ;;
  end)
;;

module Decode_llvm =
  Builder.String_option(struct
      let name = "decode-llvm"
      let doc = "Decode hexadecimal opcode as LLVM"
    end)

module CFG_graph =
  Builder.False(struct
      let name = "cfgraph"
      let doc = "Print control-flow graph"
    end
)

module Disasm_at =
  Builder.Integer(struct
      let default = 0
      let name = "at"
      let doc = "Use this address as base for opcode decoding"
    end)
