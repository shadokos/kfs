/*
 * KFS AML Operations Library
 *
 * Provides callable methods for every AML operator.
 * Use from shell:  acpi_eval \_SB._KFS._OPS.ADD_ 15 8
 * Use from tests:  Local0 = \_SB._KFS._OPS.ADD_(2, 3)
 */
DefinitionBlock ("ops.aml", "SSDT", 2, "KFS", "KFSOPS__", 1)
{
    Scope (\_SB)
    {
        Device (_KFS)
        {
            Name (_HID, "KFS00000")

            Device (_OPS)
            {
                Name (_HID, "KFSO0000")

                /* ---- Arithmetic ---- */
                Method (ADD_, 2) { Return (Arg0 + Arg1) }
                Method (SUB_, 2) { Return (Arg0 - Arg1) }
                Method (MUL_, 2) { Return (Arg0 * Arg1) }
                Method (DIV_, 2) { Return (Arg0 / Arg1) }
                Method (MOD_, 2) { Return (Arg0 % Arg1) }
                Method (SHL_, 2) { Return (Arg0 << Arg1) }
                Method (SHR_, 2) { Return (Arg0 >> Arg1) }
                Method (INC_, 1) { Local0 = Arg0 + 1  Return (Local0) }
                Method (DEC_, 1) { Local0 = Arg0 - 1  Return (Local0) }

                /* ---- Bitwise ---- */
                Method (AND_, 2) { Return (Arg0 & Arg1) }
                Method (OR__, 2) { Return (Arg0 | Arg1) }
                Method (XOR_, 2) { Return (Arg0 ^ Arg1) }
                Method (NOT_, 1) { Return (~Arg0) }

                /* ---- Comparison (return 0 or 1) ---- */
                Method (EQL_, 2) { If (Arg0 == Arg1) { Return (1) } Return (0) }
                Method (NEQ_, 2) { If (Arg0 != Arg1) { Return (1) } Return (0) }
                Method (GRT_, 2) { If (Arg0 > Arg1)  { Return (1) } Return (0) }
                Method (LSS_, 2) { If (Arg0 < Arg1)  { Return (1) } Return (0) }
                Method (GEQ_, 2) { If (Arg0 >= Arg1) { Return (1) } Return (0) }
                Method (LEQ_, 2) { If (Arg0 <= Arg1) { Return (1) } Return (0) }

                /* ---- Logical (return 0 or 1) ---- */
                Method (LAN_, 2) { If (Arg0 && Arg1) { Return (1) } Return (0) }
                Method (LOR_, 2) { If (Arg0 || Arg1) { Return (1) } Return (0) }
                Method (LNT_, 1) { If (!Arg0)        { Return (1) } Return (0) }
            }
        }
    }
}
