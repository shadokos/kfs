/*
 * AML String/Buffer Comparison Test Suite
 * Tests: LEqual, LGreater, LLess on String and Buffer operands,
 * cross-type coercion (§19.6.72, §19.3.5.7), compound forms.
 *
 * NOTE: All comparisons use Local variables to prevent iasl from
 * constant-folding string/buffer literals at compile time, which
 * would bypass the runtime comparison code entirely.
 *
 * Evaluate: acpi_eval \_SB._KFS.TSCM.MAIN
 */
DefinitionBlock ("test_compare.aml", "SSDT", 2, "KFS", "TESTCMP_", 1)
{
    External (\_SB._KFS, DeviceObj)

    Scope (\_SB._KFS)
    {
        Device (TSCM)
        {
            Name (_HID, "KFST0011")
            Name (PCNT, 0)
            Name (TCNT, 0)

            /* ---- String equality (§19.6.72) ---- */
            Method (TSEQ, 0)
            {
                /* Equal strings */
                Local0 = "abc"
                Local1 = "abc"
                If (LEqual (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0101) }

                /* Different strings */
                Local1 = "abd"
                If (LEqual (Local0, Local1)) { Return (0x0102) }
                PCNT = PCNT + 1

                /* Empty strings */
                Local0 = ""
                Local1 = ""
                If (LEqual (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0103) }

                /* Empty vs non-empty */
                Local1 = "a"
                If (LEqual (Local0, Local1)) { Return (0x0104) }
                PCNT = PCNT + 1

                /* Case sensitive */
                Local0 = "ABC"
                Local1 = "abc"
                If (LEqual (Local0, Local1)) { Return (0x0105) }
                PCNT = PCNT + 1

                /* Different lengths */
                Local0 = "ab"
                Local1 = "abc"
                If (LEqual (Local0, Local1)) { Return (0x0106) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* ---- String ordering (lexicographic) ---- */
            Method (TSGT, 0)
            {
                /* "b" > "a" */
                Local0 = "b"
                Local1 = "a"
                If (LGreater (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0201) }

                /* "a" < "b" */
                Local0 = "a"
                Local1 = "b"
                If (LLess (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0202) }

                /* "abc" < "abd" (differ at 3rd char) */
                Local0 = "abc"
                Local1 = "abd"
                If (LLess (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0203) }

                /* Prefix: "ab" < "abc" (shorter < longer when prefix matches) */
                Local0 = "ab"
                Local1 = "abc"
                If (LLess (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0204) }

                Return (0)
            }

            /* ---- Buffer equality ---- */
            Method (TBEQ, 0)
            {
                /* Equal buffers */
                Local0 = Buffer() {1, 2, 3}
                Local1 = Buffer() {1, 2, 3}
                If (LEqual (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0301) }

                /* Different content */
                Local1 = Buffer() {1, 2, 4}
                If (LEqual (Local0, Local1)) {
                    Return (0x0302)
                }
                PCNT = PCNT + 1

                /* Different lengths */
                Local0 = Buffer() {1, 2}
                Local1 = Buffer() {1, 2, 3}
                If (LEqual (Local0, Local1)) {
                    Return (0x0303)
                }
                PCNT = PCNT + 1

                /* Empty buffers */
                Local0 = Buffer(0) {}
                Local1 = Buffer(0) {}
                If (LEqual (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0304) }

                Return (0)
            }

            /* ---- Buffer ordering ---- */
            Method (TBGT, 0)
            {
                /* {2} > {1} */
                Local0 = Buffer() {2}
                Local1 = Buffer() {1}
                If (LGreater (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0401) }

                /* {1,2} < {1,3} (differ at byte 1) */
                Local0 = Buffer() {1, 2}
                Local1 = Buffer() {1, 3}
                If (LLess (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0402) }

                /* Prefix: {1,2} < {1,2,3} (shorter < longer) */
                Local0 = Buffer() {1, 2}
                Local1 = Buffer() {1, 2, 3}
                If (LLess (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0403) }

                Return (0)
            }

            /* ---- Cross-type comparison (§19.3.5.7) ----
             * String vs Integer: second operand (integer) is coerced
             * to the type of the first (string). Integer -> decimal string.
             */
            Method (TCRS, 0)
            {
                /* "255" == 255 -> "255" == "255" */
                Local0 = "255"
                Local1 = 255
                If (LEqual (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0501) }

                /* "256" > 255 -> "256" > "255" (lexicographic) */
                Local0 = "256"
                If (LGreater (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0502) }

                /* "100" < 99 -> "100" < "99" (lexicographic: "1" < "9") */
                Local0 = "100"
                Local1 = 99
                If (LLess (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0503) }

                /* "0" == 0 -> "0" == "0" */
                Local0 = "0"
                Local1 = 0
                If (LEqual (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0504) }

                Return (0)
            }

            /* ---- Compound forms on strings ---- */
            Method (TCPD, 0)
            {
                /* LNotEqual: "abc" != "abd" */
                Local0 = "abc"
                Local1 = "abd"
                If (LNotEqual (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0601) }

                /* LGreaterEqual: "abc" >= "abc" */
                Local1 = "abc"
                If (LGreaterEqual (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0602) }

                /* LGreaterEqual: "b" >= "a" */
                Local0 = "b"
                Local1 = "a"
                If (LGreaterEqual (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0603) }

                /* LLessEqual: "a" <= "b" */
                Local0 = "a"
                Local1 = "b"
                If (LLessEqual (Local0, Local1)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0604) }

                Return (0)
            }

            Method (MAIN, 0, Serialized)
            {
                PCNT = 0
                TCNT = 25

                Local0 = TSEQ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TSGT()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TBEQ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TBGT()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TCRS()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TCPD()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
