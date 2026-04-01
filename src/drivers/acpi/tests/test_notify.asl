/*
 * AML Notify Opcode Test Suite
 * Tests: Notify dispatch with various notification values,
 * Notify on child devices, execution continues after Notify.
 *
 * These are smoke tests: we verify the interpreter handles
 * Notify correctly and does not crash. The actual dispatch
 * (GPE → event queue → worker) is an integration-level concern.
 *
 * Evaluate: acpi_eval \_SB._KFS.TNFY.MAIN
 */
DefinitionBlock ("test_notify.aml", "SSDT", 2, "KFS", "TESTNFY_", 1)
{
    External (\_SB._KFS, DeviceObj)

    Scope (\_SB._KFS)
    {
        Device (TNFY)
        {
            Name (_HID, "KFST0014")
            Name (PCNT, 0)
            Name (TCNT, 0)

            /* Target device for Notify */
            Device (TDEV)
            {
                Name (_HID, "PNP0A06")
                Name (_STA, 0x0F)
            }

            /* Second target device */
            Device (TDV2)
            {
                Name (_HID, "PNP0A06")
                Name (_STA, 0x0F)
            }

            /* ---- Notify with various values (§5.6.6) ---- */
            Method (TNOT, 0)
            {
                /* Bus Check (0x00) */
                Notify (TDEV, 0)
                PCNT = PCNT + 1

                /* Device Check (0x01) */
                Notify (TDEV, 1)
                PCNT = PCNT + 1

                /* Device Wake (0x02) */
                Notify (TDEV, 2)
                PCNT = PCNT + 1

                /* Eject Request (0x03) */
                Notify (TDEV, 3)
                PCNT = PCNT + 1

                Return (0)
            }

            /* ---- Notify on different devices ---- */
            Method (TMUL, 0)
            {
                /* Notify first device */
                Notify (TDEV, 0)
                PCNT = PCNT + 1

                /* Notify second device */
                Notify (TDV2, 1)
                PCNT = PCNT + 1

                Return (0)
            }

            /* ---- Verify execution continues after Notify ---- */
            Method (TCON, 0)
            {
                Local0 = 0
                Notify (TDEV, 0)
                Local0 = 42

                /* Verify assignment after Notify worked */
                If (Local0 != 42) { Return (0x0301) }
                PCNT = PCNT + 1

                /* Arithmetic after Notify */
                Notify (TDV2, 1)
                Local1 = Local0 + 8
                If (Local1 != 50) { Return (0x0302) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (MAIN, 0, Serialized)
            {
                PCNT = 0
                TCNT = 8

                Local0 = TNOT()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TMUL()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TCON()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
