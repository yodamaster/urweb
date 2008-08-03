(* Copyright (c) 2008, Adam Chlipala
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * - The names of contributors may not be used to endorse or promote products
 *   derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *)

(* Remove unused definitions from a file *)

structure MonoShake :> MONO_SHAKE = struct

open Mono

structure U = MonoUtil

structure IS = IntBinarySet
structure IM = IntBinaryMap

type free = {
     con : IS.set,
     exp : IS.set
}

fun shake file =
    let
        val page_es = List.foldl
                          (fn ((DExport (_, _, n, _), _), page_es) => n :: page_es
                            | (_, page_es) => page_es) [] file

        val (cdef, edef) = foldl (fn ((DDatatype (_, n, xncs), _), (cdef, edef)) =>
                                     (IM.insert (cdef, n, xncs), edef)
                                   | ((DVal (_, n, t, e, _), _), (cdef, edef)) =>
                                     (cdef, IM.insert (edef, n, (t, e)))
                                   | ((DValRec vis, _), (cdef, edef)) =>
                                     (cdef, foldl (fn ((_, n, t, e, _), edef) => IM.insert (edef, n, (t, e))) edef vis)
                                   | ((DExport _, _), acc) => acc)
                                 (IM.empty, IM.empty) file

        fun typ (c, s) =
            case c of
                TDatatype (n, _) =>
                if IS.member (#con s, n) then
                    s
                else
                    let
                        val s' = {exp = #exp s,
                                  con = IS.add (#con s, n)}
                    in
                        case IM.find (cdef, n) of
                            NONE => s'
                          | SOME xncs => foldl (fn ((_, _, to), s) =>
                                                   case to of
                                                       NONE => s
                                                     | SOME t => shakeTyp s t)
                                         s' xncs
                    end
              | _ => s

        and shakeTyp s = U.Typ.fold typ s

        fun exp (e, s) =
            case e of
                ENamed n =>
                if IS.member (#exp s, n) then
                    s
                else
                    let
                        val s' = {exp = IS.add (#exp s, n),
                                  con = #con s}
                    in
                        case IM.find (edef, n) of
                            NONE => s'
                          | SOME (t, e) => shakeExp s' e
                    end
              | _ => s

        and shakeExp s = U.Exp.fold {typ = typ, exp = exp} s

        val s = {con = IS.empty, exp = IS.addList (IS.empty, page_es)}

        val s = foldl (fn (n, s) =>
                          case IM.find (edef, n) of
                              NONE => raise Fail "Shake: Couldn't find 'val'"
                            | SOME (t, e) => shakeExp s e) s page_es
    in
        List.filter (fn (DDatatype (_, n, _), _) => IS.member (#con s, n)
                      | (DVal (_, n, _, _, _), _) => IS.member (#exp s, n)
                      | (DValRec vis, _) => List.exists (fn (_, n, _, _, _) => IS.member (#exp s, n)) vis
                      | (DExport _, _) => true) file
    end

end