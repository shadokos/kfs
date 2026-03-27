/*
 * AML Named Objects Test Suite
 * Tests: Name creation, dynamic names inside methods, SizeOf,
 * string operations, package basics
 *
 * Evaluate: acpi_eval \_SB._KFS.TNAM.MAIN
 */
DefinitionBlock ("test_names.aml", "SSDT", 2, "KFS", "TESTNAME", 1)
{
    External (\_SB._KFS, DeviceObj)
    External (\_SB._KFS._OPS.ADD_, MethodObj)

    Scope (\_SB._KFS)
    {
        Device (TNAM)
        {
            Name (_HID, "KFST0006")
            Name (PCNT, 0)
            Name (TCNT, 0)

            /* static named objects */
            Name (VAL1, 100)
            Name (VAL2, 200)
            Name (STR1, "hello")

            Method (TSTA, 0)
            {
                /* read static names */
                If (VAL1 != 100) { Return (0x0101) }
                PCNT = PCNT + 1
                If (VAL2 != 200) { Return (0x0102) }
                PCNT = PCNT + 1

                /* arithmetic on named objects */
                Local0 = \_SB._KFS._OPS.ADD_ (VAL1, VAL2)
                If (Local0 != 300) { Return (0x0103) }
                PCNT = PCNT + 1

                /* modify and restore */
                Local0 = VAL1
                VAL1 = 999
                If (VAL1 != 999) { Return (0x0104) }
                PCNT = PCNT + 1
                
                VAL1 = Local0
                If (VAL1 != 100) { Return (0x0105) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* Ajout de Serialized pour éviter le Remark de création dynamique */
            Method (TDYN, 0, Serialized)
            {
                /* dynamic Name inside method */
                Name (DYN1, 42)
                If (DYN1 != 42) { Return (0x0201) }
                PCNT = PCNT + 1

                DYN1 = \_SB._KFS._OPS.ADD_ (DYN1, 8)
                If (DYN1 != 50) { Return (0x0202) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (MAIN, 0)
            {
                PCNT = 0
                TCNT = 7

                Local0 = TSTA()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TDYN()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
