/*
 * AML Conversion & Misc Opcodes Test Suite
 * Tests: ToHexString, ToDecimalString, ToBuffer, ToString,
 *        Concat, ConcatRes, Mid, Match, CondRefOf, RefOf
 *
 * NOTE: We use revision 1 (32-bit integer mode) to match the kernel.
 * Constant inputs are stored in Locals first to prevent iasl from
 * constant-folding the conversion opcodes at compile time.
 *
 * Evaluate: acpi_eval \_SB._KFS.TCNV.MAIN
 */
DefinitionBlock ("test_conv.aml", "SSDT", 1, "KFS", "TESTCONV", 1)
{
    External (\_SB._KFS, DeviceObj)

    Scope (\_SB._KFS)
    {
        Device (TCNV)
        {
            Name (_HID, "KFST0009")
            Name (PCNT, 0)
            Name (TCNT, 0)

            /* --------------------------------------------------------
             * ToHexString (§19.6.138)
             * Integer -> "0000ABCD" style hex string (8 chars, 32-bit)
             * -------------------------------------------------------- */
            Method (THEX, 0, Serialized)
            {
                /* Integer -> hex string (use Local to prevent folding) */
                Local7 = 0x00FF
                Local0 = ToHexString (Local7)
                Local1 = SizeOf (Local0)
                If (Local1 != 8) { Return (0x0101) }
                PCNT = PCNT + 1

                /* Zero -> "00000000" */
                Local7 = 0
                Local0 = ToHexString (Local7)
                Local1 = SizeOf (Local0)
                If (Local1 != 8) { Return (0x0102) }
                PCNT = PCNT + 1

                /* String -> unchanged */
                Local7 = "hello"
                Local0 = ToHexString (Local7)
                Local1 = SizeOf (Local0)
                If (Local1 != 5) { Return (0x0103) }
                PCNT = PCNT + 1

                /* Buffer -> comma-separated hex pairs */
                Local0 = ToHexString (Buffer (3) { 0xAB, 0xCD, 0xEF })
                /* "AB,CD,EF" = 8 chars */
                Local1 = SizeOf (Local0)
                If (Local1 != 8) { Return (0x0104) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* --------------------------------------------------------
             * ToDecimalString (§19.6.137)
             * Integer -> decimal ASCII string
             * -------------------------------------------------------- */
            Method (TDEC, 0, Serialized)
            {
                /* 255 -> "255" */
                Local7 = 255
                Local0 = ToDecimalString (Local7)
                Local1 = SizeOf (Local0)
                If (Local1 != 3) { Return (0x0201) }
                PCNT = PCNT + 1

                /* 0 -> "0" */
                Local7 = 0
                Local0 = ToDecimalString (Local7)
                Local1 = SizeOf (Local0)
                If (Local1 != 1) { Return (0x0202) }
                PCNT = PCNT + 1

                /* String passthrough */
                Local7 = "test"
                Local0 = ToDecimalString (Local7)
                Local1 = SizeOf (Local0)
                If (Local1 != 4) { Return (0x0203) }
                PCNT = PCNT + 1

                /* Buffer -> comma-separated decimal bytes */
                /* {0x0A, 0xFF} -> "10,255" = 6 chars */
                Local0 = ToDecimalString (Buffer (2) { 0x0A, 0xFF })
                Local1 = SizeOf (Local0)
                If (Local1 != 6) { Return (0x0204) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* --------------------------------------------------------
             * ToBuffer (§19.6.136)
             * Integer -> 4-byte LE buffer (32-bit mode)
             * -------------------------------------------------------- */
            Method (TBFR, 0, Serialized)
            {
                /* Integer -> 4-byte buffer */
                Local7 = 0x12345678
                Local0 = ToBuffer (Local7)
                Local1 = ObjectType (Local0)
                If (Local1 != 3) { Return (0x0301) }
                PCNT = PCNT + 1

                Local1 = SizeOf (Local0)
                If (Local1 != 4) { Return (0x0302) }
                PCNT = PCNT + 1

                /* Check little-endian byte order */
                Local2 = DerefOf (Index (Local0, 0))
                If (Local2 != 0x78) { Return (0x0303) }
                PCNT = PCNT + 1

                Local2 = DerefOf (Index (Local0, 3))
                If (Local2 != 0x12) { Return (0x0304) }
                PCNT = PCNT + 1

                /* Zero -> 4 zero bytes */
                Local7 = 0
                Local0 = ToBuffer (Local7)
                Local1 = SizeOf (Local0)
                If (Local1 != 4) { Return (0x0305) }
                PCNT = PCNT + 1

                Local2 = DerefOf (Index (Local0, 0))
                If (Local2 != 0) { Return (0x0306) }
                PCNT = PCNT + 1

                /* Buffer passthrough */
                Local0 = ToBuffer (Buffer (2) { 0xAA, 0xBB })
                Local1 = SizeOf (Local0)
                If (Local1 != 2) { Return (0x0307) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* --------------------------------------------------------
             * ToString (§19.6.141)
             * Buffer -> String with length limit, null termination
             * -------------------------------------------------------- */
            Method (TTOS, 0, Serialized)
            {
                /* Buffer with ASCII data */
                Name (BUF1, Buffer (5) { 0x48, 0x45, 0x4C, 0x4C, 0x4F })
                Local0 = ToString (BUF1, Ones)
                Local1 = SizeOf (Local0)
                If (Local1 != 5) { Return (0x0401) }
                PCNT = PCNT + 1

                /* Length-limited conversion */
                Local0 = ToString (BUF1, 3)
                Local1 = SizeOf (Local0)
                If (Local1 != 3) { Return (0x0402) }
                PCNT = PCNT + 1

                /* Null-terminated: buffer with embedded NUL */
                Name (BUF2, Buffer (5) { 0x41, 0x42, 0x00, 0x43, 0x44 })
                Local0 = ToString (BUF2, Ones)
                Local1 = SizeOf (Local0)
                If (Local1 != 2) { Return (0x0403) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* --------------------------------------------------------
             * Concat (§19.6.12)
             * -------------------------------------------------------- */
            Method (TCAT, 0, Serialized)
            {
                /* String + String (use Locals to prevent folding) */
                Local6 = "AB"
                Local7 = "CD"
                Local0 = Concatenate (Local6, Local7)
                Local1 = ObjectType (Local0)
                If (Local1 != 2) { Return (0x0501) }
                PCNT = PCNT + 1

                Local1 = SizeOf (Local0)
                If (Local1 != 4) { Return (0x0502) }
                PCNT = PCNT + 1

                /* Buffer + Buffer */
                Local0 = Concatenate (Buffer (2) { 0x11, 0x22 }, Buffer (2) { 0x33, 0x44 })
                Local1 = ObjectType (Local0)
                If (Local1 != 3) { Return (0x0503) }
                PCNT = PCNT + 1

                Local1 = SizeOf (Local0)
                If (Local1 != 4) { Return (0x0504) }
                PCNT = PCNT + 1

                /* Verify concatenated buffer contents */
                Local2 = DerefOf (Index (Local0, 0))
                If (Local2 != 0x11) { Return (0x0505) }
                PCNT = PCNT + 1

                Local2 = DerefOf (Index (Local0, 2))
                If (Local2 != 0x33) { Return (0x0506) }
                PCNT = PCNT + 1

                /* Integer + Integer -> 8-byte buffer (use Locals) */
                Local6 = 0x01020304
                Local7 = 0x05060708
                Local0 = Concatenate (Local6, Local7)
                Local1 = ObjectType (Local0)
                If (Local1 != 3) { Return (0x0507) }
                PCNT = PCNT + 1

                Local1 = SizeOf (Local0)
                If (Local1 != 8) { Return (0x0508) }
                PCNT = PCNT + 1

                /* First 4 bytes: LE of 0x01020304 -> 04,03,02,01 */
                Local2 = DerefOf (Index (Local0, 0))
                If (Local2 != 0x04) { Return (0x0509) }
                PCNT = PCNT + 1

                /* Byte at index 4: LE of 0x05060708 -> 08 */
                Local2 = DerefOf (Index (Local0, 4))
                If (Local2 != 0x08) { Return (0x050A) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* --------------------------------------------------------
             * Mid (§19.6.85)
             * Extract substring / sub-buffer
             * -------------------------------------------------------- */
            Method (TMID, 0, Serialized)
            {
                /* String mid (use Local to prevent folding) */
                Local7 = "ABCDEF"
                Local0 = Mid (Local7, 2, 3)
                Local1 = ObjectType (Local0)
                If (Local1 != 2) { Return (0x0601) }
                PCNT = PCNT + 1

                Local1 = SizeOf (Local0)
                If (Local1 != 3) { Return (0x0602) }
                PCNT = PCNT + 1

                /* Buffer mid */
                Local0 = Mid (Buffer (5) { 0x10, 0x20, 0x30, 0x40, 0x50 }, 1, 3)
                Local1 = ObjectType (Local0)
                If (Local1 != 3) { Return (0x0603) }
                PCNT = PCNT + 1

                Local1 = SizeOf (Local0)
                If (Local1 != 3) { Return (0x0604) }
                PCNT = PCNT + 1

                /* Check first byte of extracted sub-buffer */
                Local2 = DerefOf (Index (Local0, 0))
                If (Local2 != 0x20) { Return (0x0605) }
                PCNT = PCNT + 1

                /* Mid with index beyond length -> empty */
                Local7 = "AB"
                Local0 = Mid (Local7, 10, 5)
                Local1 = SizeOf (Local0)
                If (Local1 != 0) { Return (0x0606) }
                PCNT = PCNT + 1

                /* Mid with length exceeding remaining -> clamp */
                Local7 = "ABCDEF"
                Local0 = Mid (Local7, 4, 100)
                Local1 = SizeOf (Local0)
                If (Local1 != 2) { Return (0x0607) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* --------------------------------------------------------
             * Match (§19.6.80)
             * Search Package for matching element
             * -------------------------------------------------------- */
            Method (TMAT, 0, Serialized)
            {
                Name (PKG1, Package (5) { 10, 20, 30, 40, 50 })

                /* MEQ: find element == 30 */
                Local0 = Match (PKG1, MEQ, 30, MTR, 0, 0)
                If (Local0 != 2) { Return (0x0701) }
                PCNT = PCNT + 1

                /* MGE: find first element >= 25 */
                Local0 = Match (PKG1, MGE, 25, MTR, 0, 0)
                If (Local0 != 2) { Return (0x0702) }
                PCNT = PCNT + 1

                /* MLE + MGE: find element in range [20, 35] */
                Local0 = Match (PKG1, MGE, 20, MLE, 35, 0)
                If (Local0 != 1) { Return (0x0703) }
                PCNT = PCNT + 1

                /* Not found -> Ones (0xFFFFFFFF) */
                Local0 = Match (PKG1, MEQ, 99, MTR, 0, 0)
                If (Local0 != Ones) { Return (0x0704) }
                PCNT = PCNT + 1

                /* StartIndex: search from index 3 */
                Local0 = Match (PKG1, MGE, 10, MTR, 0, 3)
                If (Local0 != 3) { Return (0x0705) }
                PCNT = PCNT + 1

                /* MLT: find first element < 15 */
                Local0 = Match (PKG1, MLT, 15, MTR, 0, 0)
                If (Local0 != 0) { Return (0x0706) }
                PCNT = PCNT + 1

                /* MGT: find first element > 45 */
                Local0 = Match (PKG1, MGT, 45, MTR, 0, 0)
                If (Local0 != 4) { Return (0x0707) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* --------------------------------------------------------
             * CondRefOf (§19.6.14)
             * -------------------------------------------------------- */
            Method (TCRF, 0, Serialized)
            {
                Name (TST1, 42)

                /* CondRefOf on existing object -> True */
                If (CondRefOf (TST1, Local0))
                {
                    PCNT = PCNT + 1
                }
                Else
                {
                    Return (0x0801)
                }

                /* CondRefOf on non-existent name -> False */
                If (CondRefOf (ZZZZ, Local0))
                {
                    Return (0x0802)
                }
                Else
                {
                    PCNT = PCNT + 1
                }

                /* CondRefOf on initialized Local */
                Local1 = 100
                If (CondRefOf (Local1, Local2))
                {
                    PCNT = PCNT + 1
                }
                Else
                {
                    Return (0x0803)
                }

                Return (0)
            }

            /* --------------------------------------------------------
             * RefOf (§19.6.113)
             * -------------------------------------------------------- */
            Method (TREF, 0, Serialized)
            {
                Name (VAL1, 77)
                Local0 = RefOf (VAL1)
                /* RefOf returns the object itself in our model */
                If (Local0 != 77) { Return (0x0901) }
                PCNT = PCNT + 1

                /* RefOf on Local */
                Local1 = 55
                Local2 = RefOf (Local1)
                If (Local2 != 55) { Return (0x0902) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* --------------------------------------------------------
             * ConcatRes (§19.6.13)
             * Concatenate resource template buffers
             * -------------------------------------------------------- */
            Method (TCRS, 0, Serialized)
            {
                /* Two minimal resource templates, each ending with End Tag (0x79, checksum) */
                Name (RES1, Buffer (4) { 0x22, 0x00, 0x79, 0x00 })
                Name (RES2, Buffer (4) { 0x23, 0x00, 0x79, 0x00 })

                Local0 = ConcatenateResTemplate (RES1, RES2)
                Local1 = ObjectType (Local0)
                If (Local1 != 3) { Return (0x0A01) }
                PCNT = PCNT + 1

                /* Result should be: RES1 without End Tag (2 bytes) + RES2 (4 bytes) = 6 bytes */
                Local1 = SizeOf (Local0)
                If (Local1 != 6) { Return (0x0A02) }
                PCNT = PCNT + 1

                /* First byte from RES1 */
                Local2 = DerefOf (Index (Local0, 0))
                If (Local2 != 0x22) { Return (0x0A03) }
                PCNT = PCNT + 1

                /* Third byte: first byte of RES2 */
                Local2 = DerefOf (Index (Local0, 2))
                If (Local2 != 0x23) { Return (0x0A04) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* --------------------------------------------------------
             * Implicit type coercion to Integer (§19.3.5)
             * String → parse decimal/hex, Buffer → LE bytes
             * -------------------------------------------------------- */
            Method (TCOE, 0, Serialized)
            {
                /* Decimal string -> integer via Add (implicit coercion) */
                Local7 = "42"
                Local0 = Local7 + 0
                If (Local0 != 42) { Return (0x0B01) }
                PCNT = PCNT + 1

                /* Hex string -> integer */
                Local7 = "0xFF"
                Local0 = Local7 + 0
                If (Local0 != 255) { Return (0x0B02) }
                PCNT = PCNT + 1

                /* Hex string uppercase */
                Local7 = "0x1A"
                Local0 = Local7 + 0
                If (Local0 != 26) { Return (0x0B03) }
                PCNT = PCNT + 1

                /* Empty string -> 0 */
                Local7 = ""
                Local0 = Local7 + 0
                If (Local0 != 0) { Return (0x0B04) }
                PCNT = PCNT + 1

                /* Buffer -> LE integer: {0x78, 0x56, 0x34, 0x12} -> 0x12345678 */
                Local0 = Buffer (4) { 0x78, 0x56, 0x34, 0x12 } + 0
                If (Local0 != 0x12345678) { Return (0x0B05) }
                PCNT = PCNT + 1

                /* Short buffer: {0xAB} -> 0xAB */
                Local0 = Buffer (1) { 0xAB } + 0
                If (Local0 != 0xAB) { Return (0x0B06) }
                PCNT = PCNT + 1

                /* 2-byte buffer: {0xCD, 0xAB} -> 0xABCD */
                Local0 = Buffer (2) { 0xCD, 0xAB } + 0
                If (Local0 != 0xABCD) { Return (0x0B07) }
                PCNT = PCNT + 1

                /* Zero string "0" */
                Local7 = "0"
                Local0 = Local7 + 0
                If (Local0 != 0) { Return (0x0B08) }
                PCNT = PCNT + 1

                /* Large decimal string */
                Local7 = "1000"
                Local0 = Local7 + 0
                If (Local0 != 1000) { Return (0x0B09) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* ========================================================
             * MAIN entry point
             * ======================================================== */
            Method (MAIN, 0, Serialized)
            {
                PCNT = 0
                TCNT = 60

                Local0 = THEX ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TDEC ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TBFR ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TTOS ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TCAT ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TMID ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TMAT ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TCRF ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TREF ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TCRS ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TCOE ()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
