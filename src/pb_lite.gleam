import gleam/io
import gleam/list

pub type ValueType {
  VarInt(a: Int)
  Int64(a: Int)
  Binary(a: BitString)
  Group(a: List(#(Int, ValueType)))
  Int32(a: Int)
}

external fn shl(Int, Int) -> Int =
  "helper" "f_bsl"

external fn band(Int, Int) -> Int =
  "helper" "f_band"

pub fn dvarint(bin: BitString) -> Result(#(Int, BitString), Nil) {
  dvarint_1(bin, 0, 0)
}

fn dvarint_1(bin: BitString, count: Int, acc: Int) -> Result(#(Int, BitString), Nil) {
  case bin {
    <<1:size(1), i:size(7), r:binary>> -> {
      let new_acc = acc + shl(i, count * 7)
      dvarint_1(r, count + 1, new_acc)
    }

    <<0:size(1), i:size(7), r:binary>> -> {
      let num = acc + shl(i, count * 7)
      let <<signed:64-signed>> = <<num:64>>
      Ok(#(signed, r))
    }
    <<>> ->
      Error(Nil)
  }
}

//  1   64-bit  fixed64, sfixed64, double
fn dbit64(bin) {
  case bin {
    <<int64:little-signed-size(64), r:binary>> -> Ok(#(int64, r))
    _ -> Error(Nil)
  }
}

//  2   Length-delimited    string, bytes, embedded messages, packed repeated fields
fn dlen_delimited(bin) {
  try #(value, r) = dvarint(bin)
  case r {
    <<v:binary-size(value), r:binary>> -> Ok(#(v, r))
    _ -> Error(Nil)
  }
}

//  3   Start group groups (deprecated)
//  4   End group groups (deprecated)

//  5   32-bit  fixed32, sfixed32, float
fn dbit32(bin) {
  case bin {
    <<int64:little-signed-size(32), r:binary>> -> Ok(#(int64, r))
    _ -> Error(Nil)
  }
}

pub fn dtag_type(bin) {
  case bin {
    <<tag:size(5), ftype:size(3), r:binary>> ->
      case band(tag, 16) {
        16 -> {
          try #(value, r) = dvarint(r)
          let v = shl(value, 4) + band(tag, 0xF)
          Ok(#(v, ftype, r))
        }
        _ -> Ok(#(tag, ftype, r))
      }
  }
}

type KeyValueList =
  List(#(Int, ValueType))

pub fn decode(
  bin: BitString
) -> Result(#(KeyValueList, BitString), Nil) {
  decode_1(bin, [])
}
 
pub fn decode_1(
  bin: BitString,
  acc: KeyValueList,
) -> Result(#(KeyValueList, BitString), Nil) {
  case bin {
    <<>> -> Ok(#(list.reverse(acc), <<>>))
    _ -> {
      try #(tag, f_type, r) = dtag_type(bin)
      case f_type {
        0 -> {
          try #(value, r) = dvarint(r)
          let v = #(tag, VarInt(value))
          decode_1(r, [v, ..acc])
        }
        1 -> {
          try #(value, r) = dbit64(r)
          let v = #(tag, Int64(value))
          decode_1(r, [v, ..acc])
        }
        2 -> {
          try #(value, r) = dlen_delimited(r)
          let v = #(tag, Binary(value))
          decode_1(r, [v, ..acc])
        }
        3 -> {
          try #(value, r) = decode_1(r, [])
          let v = #(tag, Group(value))
          decode_1(r, [v, ..acc])
        }
        4 -> Ok(#(list.reverse(acc), r))
        5 -> {
          try #(value, r) = dbit32(r)
          let v = #(tag, Int32(value))
          decode_1(r, [v, ..acc])
        }
      }
    }
  }
}

//  def evarint(num), do: evarint(num, <<>>)
//  def evarint(num, acc) when num <= 127, do: acc <> <<0::integer-size(1), num::integer-size(7)>>
//
//  def evarint(num, acc) do
//    <<r::integer-little-size(1), n::integer-little-size(7)>> = <<num::integer-size(8)-little>>
//    acc = acc <> <<1::integer-size(1), n::integer-size(7)>>
//    evarint((num >>> 8 <<< 1) + r, acc)
//  end
//
//  def etag_type(tag, type) do
//    cond do
//      tag < 16 ->
//        <<tag::size(5), type::size(3)>>
//
//      true ->
//        btag = (tag &&& 0xF) ||| 0x10
//        <<btag::size(5), type::size(3), evarint(tag >>> 4)::binary>>
//    end
//  end
//
//  def encode(proplists), do: encode(proplists, <<>>)
//  def encode([], acc), do: acc
//
//  def encode([data | rest], acc) do
//    acc =
//      case data do
//        {:varint, tag, n} ->
//          acc <> etag_type(tag, 0) <> evarint(n)
//
//        {:int64, tag, n} ->
//          acc <> etag_type(tag, 1) <> <<n::little-size(64)>>
//
//        {:binary, tag, n} ->
//          acc <> etag_type(tag, 2) <> evarint(byte_size(n)) <> n
//
//        {:group, tag, n} ->
//          acc <> etag_type(tag, 3) <> encode(n) <> etag_type(tag, 4)
//
//        {:int32, tag, n} ->
//          # IO.inspect {acc, etag_type(tag, 5), n}
//          acc <> etag_type(tag, 5) <> <<n::little-size(32)>>
//      end
//
//    encode(rest, acc)
//  end
//
//  # Dangerous! dont use often
//  def to_map(proplist) do
//    Enum.reduce(proplist, %{}, fn
//      {type, tag, value}, a ->
//        v =
//          case type do
//            :group -> to_map(value)
//            _ -> value
//          end
//
//        case Map.has_key?(a, tag) do
//          false ->
//            Map.merge(a, %{tag => v})
//
//          true ->
//            oldV = Map.get(a, tag)
//
//            v =
//              if is_list(oldV) do
//                oldV ++ [v]
//              else
//                [oldV, v]
//              end
//
//            Map.merge(a, %{tag => v})
//        end
//    end)
//  end
