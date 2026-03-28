/*
 * AML Data Structures Test Suite
 * Tests: Strings, Buffers, Packages, SizeOf, ObjectType,
 * Index, DerefOf, dynamic element access, and nested packages.
 *
 * Evaluate: acpi_eval \_SB._KFS.TDAT.MAIN
 */
DefinitionBlock ("test_data.aml", "SSDT", 2, "KFS", "TESTDATA", 1)
{
    External (\_SB._KFS, DeviceObj)

    Scope (\_SB._KFS)
    {
        Device (TDAT)
        {
            Name (_HID, "KFST0007")
            Name (PCNT, 0)
            Name (TCNT, 0)

            /* * ObjectType returns:
             * 1 = Integer
             * 2 = String
             * 3 = Buffer
             * 4 = Package
             */

            Method (TSTR, 0, Serialized)
            {
                /* Test String size and type */
                Name (STR1, "KFS-OS")
                
                Local0 = ObjectType (STR1)
                If (Local0 != 2) { Return (0x0101) }
                PCNT = PCNT + 1

                Local0 = SizeOf (STR1)
                If (Local0 != 6) { Return (0x0102) }
                PCNT = PCNT + 1

                /* Empty string */
                Name (STR2, "")
                Local0 = SizeOf (STR2)
                If (Local0 != 0) { Return (0x0103) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TBUF, 0, Serialized)
            {
                /* Test Buffer size, type and index reading */
                Name (BUF1, Buffer (4) { 0xDE, 0xAD, 0xBE, 0xEF })

                Local0 = ObjectType (BUF1)
                If (Local0 != 3) { Return (0x0201) }
                PCNT = PCNT + 1

                Local0 = SizeOf (BUF1)
                If (Local0 != 4) { Return (0x0202) }
                PCNT = PCNT + 1

                /* Test reading from buffer via Index/DerefOf */
                Local1 = DerefOf (Index (BUF1, 0))
                If (Local1 != 0xDE) { Return (0x0203) }
                PCNT = PCNT + 1

                Local1 = DerefOf (Index (BUF1, 2))
                If (Local1 != 0xBE) { Return (0x0204) }
                PCNT = PCNT + 1

                /* Writing to a buffer via Index */
                Index (BUF1, 3) = 0xAA
                Local1 = DerefOf (Index (BUF1, 3))
                If (Local1 != 0xAA) { Return (0x0205) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TPKG, 0, Serialized)
            {
                /* Test Package creation, size, and mixed types */
                Name (PKG1, Package (3) 
                { 
                    42, 
                    "test", 
                    Buffer (2) { 0x11, 0x22 } 
                })

                Local0 = ObjectType (PKG1)
                If (Local0 != 4) { Return (0x0301) }
                PCNT = PCNT + 1

                Local0 = SizeOf (PKG1)
                If (Local0 != 3) { Return (0x0302) }
                PCNT = PCNT + 1

                /* Element 0: Integer */
                Local1 = DerefOf (Index (PKG1, 0))
                If (Local1 != 42) { Return (0x0303) }
                PCNT = PCNT + 1

                /* Element 1: String */
                Local1 = ObjectType (DerefOf (Index (PKG1, 1)))
                If (Local1 != 2) { Return (0x0304) }
                PCNT = PCNT + 1

                /* Element 2: Buffer */
                Local1 = ObjectType (DerefOf (Index (PKG1, 2)))
                If (Local1 != 3) { Return (0x0305) }
                PCNT = PCNT + 1

                /* Modify Package Element */
                Index (PKG1, 0) = 99
                Local1 = DerefOf (Index (PKG1, 0))
                If (Local1 != 99) { Return (0x0306) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TNST, 0, Serialized)
            {
                /* Test Nested Packages (very common in ACPI, e.g., _PRT) */
                Name (PKG2, Package (2)
                {
                    Package (2) { 11, 22 },
                    Package (2) { 33, 44 }
                })

                /* Extract the second inner package */
                Local0 = DerefOf (Index (PKG2, 1))
                Local1 = ObjectType (Local0)
                If (Local1 != 4) { Return (0x0401) } /* Should be a Package (4) */
                PCNT = PCNT + 1

                /* Extract the first element of that inner package */
                Local2 = DerefOf (Index (Local0, 0))
                If (Local2 != 33) { Return (0x0402) }
                PCNT = PCNT + 1

                /* Extract an element directly using chained Index/DerefOf */
                Local3 = DerefOf (Index (DerefOf (Index (PKG2, 0)), 1))
                If (Local3 != 22) { Return (0x0403) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TIDX, 0, Serialized)
            {
                /* Index with Target: result stored into Local via Target */
                Name (BUF1, Buffer (4) { 0xAA, 0xBB, 0xCC, 0xDD })

                /* Index writes to Target (3rd argument) */
                Index (BUF1, 2, Local0)
                /* Local0 should receive the indexed element value */
                If (Local0 != 0xCC) { Return (0x0501) }
                PCNT = PCNT + 1

                /* Index into Package with Target */
                Name (PKG1, Package (3) { 11, 22, 33 })
                Index (PKG1, 1, Local1)
                If (Local1 != 22) { Return (0x0502) }
                PCNT = PCNT + 1

                /* Index into String with Target */
                Name (STR1, "ABCD")
                Index (STR1, 0, Local2)
                /* 'A' = 0x41 */
                If (Local2 != 0x41) { Return (0x0503) }
                PCNT = PCNT + 1

                /* Index with Target + DerefOf should both work */
                Local3 = DerefOf (Index (BUF1, 3))
                If (Local3 != 0xDD) { Return (0x0504) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (MAIN, 0)
            {
                PCNT = 0
                TCNT = 21

                Local0 = TSTR()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TBUF()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TPKG()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TNST()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TIDX()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
