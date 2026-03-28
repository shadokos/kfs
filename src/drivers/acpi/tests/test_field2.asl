/*
 * AML Advanced Field Test Suite
 * Tests: UpdateRule (Preserve/WriteAsOnes/WriteAsZeros),
 * BankField, CreateField variants, IndexField.
 *
 * Uses physical address 0x700 (separate from test_hw.asl's 0x600).
 *
 * Evaluate: acpi_eval \_SB._KFS.TFD2.MAIN
 */
DefinitionBlock ("test_field2.aml", "SSDT", 2, "KFS", "TESTFLD2", 1)
{
    External (\_SB._KFS, DeviceObj)

    Scope (\_SB._KFS)
    {
        Device (TFD2)
        {
            Name (_HID, "KFST0013")
            Name (PCNT, 0)
            Name (TCNT, 0)

            /* ---- Regions for UpdateRule tests ---- */
            OperationRegion (RGN1, SystemMemory, 0x700, 16)

            /* Full-byte view for setup and verification */
            Field (RGN1, ByteAcc, NoLock, Preserve)
            {
                FUL0, 8,       /* byte 0: full byte */
                FUL1, 8,       /* byte 1: full byte */
                FUL2, 8,       /* byte 2: full byte */
            }

            /* Sub-byte field with Preserve rule */
            Field (RGN1, ByteAcc, NoLock, Preserve)
            {
                PRV0, 4,       /* byte 0, lower nibble, Preserve */
            }

            /* Sub-byte field with WriteAsOnes rule */
            Field (RGN1, ByteAcc, NoLock, WriteAsOnes)
            {
                Offset (1),
                WAO0, 4,       /* byte 1, lower nibble, WriteAsOnes */
            }

            /* Sub-byte field with WriteAsZeros rule */
            Field (RGN1, ByteAcc, NoLock, WriteAsZeros)
            {
                Offset (2),
                WAZ0, 4,       /* byte 2, lower nibble, WriteAsZeros */
            }

            /* ---- UpdateRule Preserve ---- */
            Method (TPRV, 0, Serialized)
            {
                /* Setup: write 0xFF to full byte */
                FUL0 = 0xFF

                /* Write 0x05 to lower nibble (Preserve upper) */
                PRV0 = 0x05

                /* Read full byte: upper nibble should be preserved (0xF) */
                Local0 = FUL0
                If (Local0 != 0xF5) { Return (0x0101) }
                PCNT = PCNT + 1

                /* Setup: write 0xAB */
                FUL0 = 0xAB
                PRV0 = 0x03
                Local0 = FUL0
                /* Upper nibble 0xA preserved, lower nibble 0x3 */
                If (Local0 != 0xA3) { Return (0x0102) }
                PCNT = PCNT + 1

                /* Read back sub-byte field */
                Local0 = PRV0
                If (Local0 != 0x03) { Return (0x0103) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* ---- UpdateRule WriteAsOnes ---- */
            Method (TWAO, 0, Serialized)
            {
                /* Setup: write 0xAB to byte 1 */
                FUL1 = 0xAB

                /* Write 0x05 to lower nibble (WriteAsOnes for upper) */
                WAO0 = 0x05

                /* Upper nibble should become 0xF (ones), lower = 0x5 */
                Local0 = FUL1
                If (Local0 != 0xF5) { Return (0x0201) }
                PCNT = PCNT + 1

                /* Read back sub-byte */
                Local0 = WAO0
                If (Local0 != 0x05) { Return (0x0202) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* ---- UpdateRule WriteAsZeros ---- */
            Method (TWAZ, 0, Serialized)
            {
                /* Setup: write 0xAB to byte 2 */
                FUL2 = 0xAB

                /* Write 0x05 to lower nibble (WriteAsZeros for upper) */
                WAZ0 = 0x05

                /* Upper nibble should become 0x0 (zeros), lower = 0x5 */
                Local0 = FUL2
                If (Local0 != 0x05) { Return (0x0301) }
                PCNT = PCNT + 1

                /* Read back sub-byte */
                Local0 = WAZ0
                If (Local0 != 0x05) { Return (0x0302) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* ---- BankField ---- */
            OperationRegion (BRGN, SystemMemory, 0x710, 8)
            Field (BRGN, ByteAcc, NoLock, Preserve)
            {
                BSEL, 8,       /* bank selector at offset 0 */
                BDAT, 8,       /* data byte at offset 1 */
            }

            BankField (BRGN, BSEL, 0, ByteAcc, NoLock, Preserve)
            {
                Offset (1),
                BK0D, 8,       /* data at offset 1, bank 0 */
            }

            BankField (BRGN, BSEL, 1, ByteAcc, NoLock, Preserve)
            {
                Offset (1),
                BK1D, 8,       /* data at offset 1, bank 1 */
            }

            Method (TBNK, 0, Serialized)
            {
                /* Write via bank 0: should set BSEL=0, then write data */
                BK0D = 0xAA
                Local0 = BSEL
                If (Local0 != 0) { Return (0x0401) }
                PCNT = PCNT + 1

                /* Verify data written */
                Local0 = BDAT
                If (Local0 != 0xAA) { Return (0x0402) }
                PCNT = PCNT + 1

                /* Write via bank 1: should set BSEL=1, then write data */
                BK1D = 0xBB
                Local0 = BSEL
                If (Local0 != 1) { Return (0x0403) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* ---- CreateField variants ---- */
            Method (TCRF, 0, Serialized)
            {
                Name (FBUF, Buffer() {0x78, 0x56, 0x34, 0x12})

                /* CreateByteField */
                CreateByteField (FBUF, 0, BF00)
                Local0 = BF00
                If (Local0 != 0x78) { Return (0x0501) }
                PCNT = PCNT + 1

                /* CreateWordField */
                CreateWordField (FBUF, 0, WF00)
                Local0 = WF00
                If (Local0 != 0x5678) { Return (0x0502) }
                PCNT = PCNT + 1

                /* CreateDWordField */
                CreateDWordField (FBUF, 0, DF00)
                Local0 = DF00
                If (Local0 != 0x12345678) { Return (0x0503) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* ---- IndexField ---- */
            OperationRegion (IRGN, SystemMemory, 0x720, 4)
            Field (IRGN, ByteAcc, NoLock, Preserve)
            {
                IIDX, 8,       /* index register at offset 0 */
                IDAT, 8,       /* data register at offset 1 */
            }

            IndexField (IIDX, IDAT, ByteAcc, NoLock, Preserve)
            {
                IDX0, 8,       /* index 0 */
                IDX1, 8,       /* index 1 */
                IDX2, 8,       /* index 2 */
            }

            Method (TIDX, 0, Serialized)
            {
                /* Write via IndexField: should set index reg then write data */
                IDX0 = 0x42
                /* After writing IDX0, index register should be 0 */
                Local0 = IIDX
                If (Local0 != 0) { Return (0x0601) }
                PCNT = PCNT + 1

                /* Write to index 2 */
                IDX2 = 0x99
                Local0 = IIDX
                If (Local0 != 2) { Return (0x0602) }
                PCNT = PCNT + 1

                /* Read back: sets index, then reads data */
                Local0 = IDX2
                If (Local0 != 0x99) { Return (0x0603) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (MAIN, 0, Serialized)
            {
                PCNT = 0
                TCNT = 16

                Local0 = TPRV()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TWAO()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TWAZ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TBNK()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TCRF()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TIDX()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
