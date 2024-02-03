// bytecode of the \_S5_ object
// -----------------------------------------
//        | (optional) |    |    |    |
// NameOP | \          | _  | S  | 5  | _
// 08     | 5A         | 5F | 53 | 35 | 5F
//
// -----------------------------------------------------------------------------------------------------------
//           |           |              | ( SLP_TYPa   ) | ( SLP_TYPb   ) | ( Reserved   ) | (Reserved    )
// PackageOP | PkgLength | NumElements  | byteprefix Num | byteprefix Num | byteprefix Num | byteprefix Num
// 12        | 0A        | 04           | 0A         05  | 0A          05 | 0A         05  | 0A         05
//
//----this-structure-was-also-seen----------------------
// PackageOP | PkgLength | NumElements |
// 12        | 06        | 04          | 00 00 00 00
//
// (Pkglength bit 6-7 encode additional PkgLength bytes [shouldn't be the case here])
//
// 20.2.4 Package Length Encoding
   // PkgLength :=
   // 	PkgLeadByte |
   // 	<pkgleadbyte bytedata> |
   // 	<pkgleadbyte bytedata bytedata> |
   // 	<pkgleadbyte bytedata bytedata bytedata>
   // PkgLeadByte :=
   // 	<bit 7-6: bytedata count that follows (0-3)>
   // 	<bit 5-4: only used if pkglength < 63>
   // 	<bit 3-0: least significant package length nybble>

pub const S5Object = extern struct {
	package_op: u8,
	pkg_length: u8,
	num_elements: u8,
	slp_typ_a_byteprefix: u8,
	slp_typ_a_num: u8,
	slp_typ_b_byteprefix: u8,
	slp_typ_b_num: u8,
};
