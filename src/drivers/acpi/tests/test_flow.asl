/*
 * AML Control Flow Test Suite
 * Tests: If/Else, While, Break, nested If, early Return,
 * nested While, While with counter, complex predicates
 *
 * Evaluate: acpi_eval \_SB._KFS.TFLW.MAIN
 */
DefinitionBlock ("test_flow.aml", "SSDT", 2, "KFS", "TESTFLOW", 1)
{
    External (\_SB._KFS, DeviceObj)
    External (\_SB._KFS._OPS.ADD_, MethodObj)
    External (\_SB._KFS._OPS.SUB_, MethodObj)
    External (\_SB._KFS._OPS.EQL_, MethodObj)
    External (\_SB._KFS._OPS.GRT_, MethodObj)
    External (\_SB._KFS._OPS.LEQ_, MethodObj)
    External (\_SB._KFS._OPS.LSS_, MethodObj)

    Scope (\_SB._KFS)
    {
        Device (TFLW)
        {
            Name (_HID, "KFST0003")
            Name (PCNT, 0)
            Name (TCNT, 0)

            Method (TIFF, 0)
            {
                /* true branch */
                If (1)
                {
                    Local0 = 1
                }
                Else
                {
                    Local0 = 2
                }
                If (Local0 != 1) { Return (0x0101) }
                PCNT = PCNT + 1

                /* false branch */
                If (0)
                {
                    Local0 = 3
                }
                Else
                {
                    Local0 = 4
                }
                If (Local0 != 4) { Return (0x0102) }
                PCNT = PCNT + 1

                /* If without Else (true) */
                Local0 = 10
                If (1)
                {
                    Local0 = 20
                }
                If (Local0 != 20) { Return (0x0103) }
                PCNT = PCNT + 1

                /* If without Else (false) — Local0 unchanged */
                Local0 = 30
                If (0)
                {
                    Local0 = 40
                }
                If (Local0 != 30) { Return (0x0104) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TWHL, 0)
            {
                /* count to 10 */
                Local0 = 0
                Local1 = 10
                While (\_SB._KFS._OPS.GRT_ (Local1, 0))
                {
                    Local0 = \_SB._KFS._OPS.ADD_ (Local0, 1)
                    Local1 = \_SB._KFS._OPS.SUB_ (Local1, 1)
                }
                If (Local0 != 10) { Return (0x0201) }
                PCNT = PCNT + 1
                If (Local1 != 0) { Return (0x0202) }
                PCNT = PCNT + 1

                /* sum 1..5 */
                Local0 = 0
                Local1 = 1
                While (\_SB._KFS._OPS.LEQ_ (Local1, 5))
                {
                    Local0 = \_SB._KFS._OPS.ADD_ (Local0, Local1)
                    Local1 = \_SB._KFS._OPS.ADD_ (Local1, 1)
                }
                If (Local0 != 15) { Return (0x0203) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TBRK, 0)
            {
                /* While(1) with Break */
                Local0 = 0
                While (1)
                {
                    Local0 = \_SB._KFS._OPS.ADD_ (Local0, 1)
                    If (\_SB._KFS._OPS.EQL_ (Local0, 5))
                    {
                        Break
                    }
                }
                If (Local0 != 5) { Return (0x0301) }
                PCNT = PCNT + 1

                /* Break on first iteration */
                Local0 = 0
                While (1)
                {
                    Local0 = 99
                    Break
                }
                If (Local0 != 99) { Return (0x0302) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TNST, 0)
            {
                /* deeply nested If */
                Local0 = 10
                If (\_SB._KFS._OPS.GRT_ (Local0, 5))
                {
                    If (\_SB._KFS._OPS.GRT_ (Local0, 8))
                    {
                        If (\_SB._KFS._OPS.GRT_ (Local0, 9))
                        {
                            Local1 = 1
                        }
                        Else
                        {
                            Local1 = 2
                        }
                    }
                    Else
                    {
                        Local1 = 3
                    }
                }
                Else
                {
                    Local1 = 4
                }
                If (Local1 != 1) { Return (0x0401) }
                PCNT = PCNT + 1

                /* chained If/Else as elif */
                Local0 = 2
                If (\_SB._KFS._OPS.EQL_ (Local0, 1))
                {
                    Local1 = 10
                }
                Else
                {
                    If (\_SB._KFS._OPS.EQL_ (Local0, 2))
                    {
                        Local1 = 20
                    }
                    Else
                    {
                        Local1 = 30
                    }
                }
                If (Local1 != 20) { Return (0x0402) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TRET, 0)
            {
                /* early return from middle */
                Local0 = 1
                If (\_SB._KFS._OPS.EQL_ (Local0, 1))
                {
                    PCNT = PCNT + 1
                    Return (0)
                }
                Return (0x0501)
            }

            Method (TNWH, 0)
            {
                /* nested while: multiplication table check */
                /* compute 3 * 4 by repeated addition */
                Local0 = 0  /* result */
                Local1 = 0  /* outer counter */
                While (\_SB._KFS._OPS.LSS_ (Local1, 3))
                {
                    Local2 = 0  /* inner counter */
                    While (\_SB._KFS._OPS.LSS_ (Local2, 4))
                    {
                        Local0 = \_SB._KFS._OPS.ADD_ (Local0, 1)
                        Local2 = \_SB._KFS._OPS.ADD_ (Local2, 1)
                    }
                    Local1 = \_SB._KFS._OPS.ADD_ (Local1, 1)
                }
                If (Local0 != 12) { Return (0x0601) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (MAIN, 0, Serialized)
            {
                PCNT = 0
                TCNT = 13

                Local0 = TIFF()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TWHL()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TBRK()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TNST()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TRET()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TNWH()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
