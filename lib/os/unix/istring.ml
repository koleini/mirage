(*
 * Copyright (c) 2010 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

module Raw = struct
  type t

  (* Allocate an istring, via malloc *)
  external alloc: int -> t = "caml_alloc_istring"

  (* Get total size of an istring buffer.  *)
  external size: t -> int = "caml_istring_size" "noalloc"

  (* Set character. 
     Cannot be noalloc as it can raise an exception.
  *)
  external set_byte: t -> int -> int -> unit = "caml_istring_safe_set_byte"

  (* Set uint16 big endian. *)
  external set_uint16_be: t -> int -> int -> unit = "caml_istring_set_uint16_be"

  (* Set uint32 big endian. *)
  external set_uint32_be: t -> int -> int32 -> unit = "caml_istring_set_uint32_be"

  (* Set uint64 big endian. *)
  external set_uint64_be: t -> int -> int64 -> unit = "caml_istring_set_uint64_be"

  (* Get character.
     Cannot be noalloc as it can raise an exception
   *)
  external to_char: t -> int -> char = "caml_istring_safe_get_char"

  (* Get an OCaml string slice. *)
  external to_string: t -> int -> int -> string = "caml_istring_safe_get_string"

  (* Blit string to istring.
     Cannot be noalloc as it can raise an exception *)
  external blit: t -> int -> string -> unit = "caml_istring_safe_blit"

  (* Blit istring to istring.
     Cannot be noalloc as it can raise an exception *)
  external blit_istring: t -> int -> t -> int -> int -> unit = "caml_istring_safe_blit_view"

  (* Get a big-endian uint16 out of the view *)
  external to_uint16_be: t -> int -> int = "caml_istring_get_uint16_be"

  (* Get a big-endian uint32 out of the view *)
  external to_uint32_be: t -> int -> int32 = "caml_istring_get_uint32_be"

  (* Get a big-endian uint64 out of the view *)
  external to_uint64_be: t -> int -> int64 = "caml_istring_get_uint64_be"
end

module View = struct

  (* A view into a portion of an istring *)
  type t = { 
    i: Raw.t;          (* Reference to immutable string *)
    off: int;          (* Start offset within the istring *)
    mutable len: int;  (* Valid size of istring relative to offset *)
  }
  and 'a data =
  [
    | `Sub of (t -> 'a)
    | `Str of string
    | `Frag of t
    | `None
  ]

  (* Get length of the view *)
  let length t = t.len
 
  (* Generate a sub-view.
     TODO: validate len (autogenerated in MPL right now, so partly safe) 
     TODO: increment ref count on underlying Raw.t.
   *)
  let sub t off len = { t with off=t.off+off; len=len }

  (* Copy a view.
     TODO: increment ref count on underlying Raw.t *)
  let copy t = { i=t.i; off=t.off; len=t.len }

  (** Marshal functions *)

  (* Append an OCaml string into the view *)
  let append_string t src =
    Raw.blit t.i (t.off+t.len) src;
    t.len <- String.length src + t.len

  (* Append another view into this view.
     TODO: extremely undefined behaviour if the views are the same -avsm *)
  let append_view dst src =
    Raw.blit_istring dst.i (dst.off+dst.len) src.i src.off src.len;
    dst.len <- src.len + dst.len

  (* Append a byte to the view *)
  let append_byte t v =
    Raw.set_byte t.i t.off v;
    t.len <- t.len + 1

  (* Append a uint16 to the view *)
  let append_uint16_be t v =
    Raw.set_uint16_be t.i t.off v;
    t.len <- t.len + 2

  (* Append a uint32 to the view *)
  let append_uint32_be t v =
    Raw.set_uint32_be t.i t.off v;
    t.len <- t.len + 4

  (* Append a uint64 to the view *)
  let append_uint64_be t v =
    Raw.set_uint64_be t.i t.off v;
    t.len <- t.len + 8

  (** Unmarshal functions *)

  (* Get a single character from the view *)
  let to_char t off = Raw.to_char t.i (t.off+off)

  (* Copy out an OCaml string from the view *)
  let to_string t off len = Raw.to_string t.i t.off len

  (* Get a single byte from the view, as an OCaml int.
     TODO: tempted to replace by an ADT B_1|B_2|B_3|..|B_255 :) -avsm *)
  let to_byte t off = int_of_char (to_char t off)

  (* Get a uint16 out of the view.
     TODO: big-endian only on the wire. *)
  let to_uint16_be t off = Raw.to_uint16_be t off 

  (* Get a uint32 out of the view.
     TODO: big-endian only on the wire. *)
  let to_uint32_be t off = Raw.to_uint32_be t off 

  (* Get a uint64 out of the view.
     TODO: big-endian only on the wire. *)
  let to_uint64_be t off = Raw.to_uint64_be t off 

end

module Prettyprint = struct

  open Printf

  (* A rough-n-ready hexdump from a string *)
  let hexdump s = 
    let open Buffer in
    let buf1 = create 64 in
    let buf2 = create 64 in
    let lines1 = ref [] in
    let lines2 = ref [] in
    for i = 0 to String.length s - 1 do
      if i <> 0 && (i mod 8) = 0 then begin
        lines1 := contents buf1 :: !lines1;
        lines2 := contents buf2 :: !lines2;
        reset buf1;
        reset buf2;
      end;
    let pchar c =
      let s = String.make 1 c in if Char.escaped c = s then s else "." in
      add_string buf1 (sprintf " %02X" (int_of_char (String.get s i)));
      add_string buf2 (sprintf " %s" (pchar (String.get s i)));
    done;
    if length buf1 > 0 then lines1 := contents buf1 :: !lines1;
    if length buf2 > 0 then lines2 := contents buf2 :: !lines2;
    reset buf1;
    add_char buf1 '\n';
    List.iter2 (fun l1 l2 ->
      add_string buf1 (sprintf "   %-24s   |   %-16s   \n" l1 l2);
    ) (List.rev !lines1) (List.rev !lines2);
    contents buf1

  let byte = sprintf "%u"
  let uint16 = sprintf "%u"
  let uint32 = sprintf "%lu"
  let uint64 = sprintf "%Lu"

end