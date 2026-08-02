"""Generate the Asset Overview seed data consumed by the SQLite migrations.

Reads ``Asset_Overview_v4.xlsx`` (the portfolio workbook maintained by
613 Investment Group GmbH) and emits
``lib/data/sqlite/seed/asset_overview_seed_data.dart``.

The workbook is the single source of truth for the portfolio baseline. Only the
master sheets are read; the per-asset sheets (``A001 Allee 7`` etc.) are derived
views inside the workbook and carry no additional facts.

Usage (from the repo root):

    python -m pip install openpyxl
    python tool/generate_asset_overview_seed.py path/to/Asset_Overview_v4.xlsx

Run this whenever a new workbook revision arrives, then review the diff of the
generated Dart file.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import pathlib
import sys
from typing import Any, Iterable

import openpyxl

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_PATH = REPO_ROOT / "lib" / "data" / "sqlite" / "seed" / "asset_overview_seed_data.dart"

# Property ids that earlier workbook revisions seeded and that v4 no longer
# contains. The migration purges them so stale demo objects disappear.
RETIRED_PROPERTY_IDS = ["A015", "A016", "A018"]

# The workbook labels asset types in English. The app stores a canonical
# `property_type` value that `propertyKindFromType` (lib/core/models/property.dart)
# recognises — anything it does not know falls back to "Sonstiges Objekt". So the
# workbook type maps onto the app value here, and the human-readable German label
# is kept separately for the property note.
ASSET_TYPE_TO_APP_VALUE = {
    "apartment building": "multifamily",
    "residential building": "residential",
    "mixed object": "mixed",
    "hotel": "hotel",
    "commercial building": "commercial",
    "commercial": "commercial",
}

ASSET_TYPE_GERMAN_LABEL = {
    "apartment building": "Mehrfamilienhaus",
    "residential building": "Wohnhaus",
    "mixed object": "Mischobjekt",
    "hotel": "Hotel",
    "commercial building": "Gewerbeobjekt",
    "commercial": "Gewerbe",
}

# The landlord that owns the whole portfolio (from the workbook masthead).
PORTFOLIO_OWNER = "613 Investment Group GmbH"

STATUS_LABELS = {
    "active": "Aktiv",
    "under examination": "In Prüfung",
    "sold": "Verkauft",
    "shut down": "Stillgelegt",
}

INSURANCE_TYPE_LABELS = {
    "building": "Gebäudeversicherung",
    "liability": "Haftpflichtversicherung",
    "inventory": "Inventarversicherung",
    "business interruption": "Betriebsunterbrechungsversicherung",
    "electronics": "Elektronikversicherung",
}

RENOVATION_CATEGORY_LABELS = {
    "renovation": "Renovierung",
    "modernization": "Modernisierung",
    "maintenance": "Instandhaltung",
    "fire protection": "Brandschutz",
    "furnishing": "Möblierung",
    "technical systems": "Technische Anlagen",
}

RENOVATION_STATUS_LABELS = {
    "planned": "Geplant",
    "started": "Gestartet",
    "offers open": "Angebote offen",
    "finished": "Abgeschlossen",
    "stopped": "Gestoppt",
}

# Building_Side_Costs: column index -> (cost type label, is_yearly)
BUILDING_COST_COLUMNS = [
    (2, "Grundsteuer"),
    (3, "Abfallentsorgung"),
    (5, "Straßenreinigung"),
    (7, "Niederschlagswasser"),
    (9, "Abwasser / Kanal"),
    (11, "Facility Management"),
    (12, "Reinigung"),
    (13, "Schornsteinfeger"),
]

UTILITY_TYPE_LABELS = {"S": "Strom", "W": "Wasser", "G": "Gas", "F": "Fernwärme"}

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

HOTEL_COST_COLUMNS = [
    (3, "Tilgung / Zinsen"),
    (4, "Wäscherei"),
    (5, "Reinigung & Verbrauch"),
    (6, "Brandschutz"),
    (7, "ARD/ZDF"),
    (8, "Internet"),
    (9, "Sonstiges / Reparaturen"),
    (10, "Personal"),
    (11, "Software"),
    (12, "Buchungsportale"),
]

# Rent_Payments_2026 rows keyed by normalised tenant name -> (asset id, unit code).
# The payment sheet identifies rows by tenant plus a free-text address, so the
# join to the rent roll is spelled out here rather than guessed at runtime.
PAYMENT_ROW_TO_UNIT = {
    "ufuk lyen / monkey": ("A003", "EG left"),
    "mueller": ("A003", "3. OG Left"),
    "beata ursula cwik": ("A003", "3. OG Mid"),
    "daniel kedzia": ("A003", "3. OG Right"),
    "andrej michaelik": ("A003", "3. OG Right"),
    "rafal czembor": ("A003", "3. OG Right"),
    "slawomir lukasz stando": ("A006", "2. OG"),
    "januz loskot": ("A006", "2. OG"),
    "sczepian gal": ("A006", "1. OG left"),
    "dariusz cesarski": ("A006", "1. OG left"),
    "nustri": ("A006", "1. OG Right"),
    "raffaele randazzo": ("A006", "EG"),
    "herppich kg / backery": ("A010", "EG"),
    "kiosk": ("A019", "Kiosk"),
    "steen": ("A002", "Flat 8"),
}

# Payment rows that intentionally have no rent-roll counterpart (former tenants
# and a vacancy placeholder). Listed so the generator can assert nothing else
# silently drops out.
PAYMENT_ROWS_WITHOUT_UNIT = {"loom discotheque", "infinity bar", "infinity old"}


# --------------------------------------------------------------------------- #
# cell helpers
# --------------------------------------------------------------------------- #


def text(value: Any) -> str | None:
    """Return a trimmed string, or None for blanks and spreadsheet zero-fills."""
    if value is None:
        return None
    if isinstance(value, float) and value == 0:
        return None
    if isinstance(value, dt.datetime):
        return None
    out = str(value).strip()
    if out in {"", "0", "0.0", "00:00:00"}:
        return None
    return out


def number(value: Any) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).replace(",", "."))
    except ValueError:
        return None


def positive(value: Any) -> float | None:
    result = number(value)
    if result is None or result == 0:
        return None
    return result


def integer(value: Any) -> int | None:
    result = number(value)
    return None if result is None else int(round(result))


def iso_date(value: Any) -> str | None:
    """Normalise a workbook date to ISO. Handles real dates and dd.mm.yyyy text."""
    if isinstance(value, dt.datetime):
        if value.year <= 1900:
            return None
        return value.date().isoformat()
    if isinstance(value, dt.date):
        return value.isoformat()
    raw = text(value)
    if raw is None:
        return None
    for fmt in ("%d.%m.%Y", "%d-%b-%y", "%Y-%m-%d"):
        try:
            return dt.datetime.strptime(raw, fmt).date().isoformat()
        except ValueError:
            continue
    return None


def rounded(value: float | None, digits: int = 2) -> float | None:
    return None if value is None else round(value, digits)


def normalise(value: Any) -> str:
    return " ".join(str(value or "").split()).strip().lower()


def money(value: float, suffix: str = "€") -> str:
    """Format as de-DE currency: 1.300.000,00 €."""
    formatted = f"{value:,.2f}".replace(",", "\x00").replace(".", ",").replace("\x00", ".")
    return f"{formatted} {suffix}".strip()


def rows_of(sheet, first_data_row: int) -> Iterable[tuple[int, tuple]]:
    """Yield (excel_row_number, values) for non-empty rows."""
    for index, values in enumerate(sheet.iter_rows(values_only=True), start=1):
        if index < first_data_row:
            continue
        if all(cell is None or str(cell).strip() == "" for cell in values):
            continue
        yield index, values


def cell(values: tuple, index: int) -> Any:
    return values[index] if index < len(values) else None


# --------------------------------------------------------------------------- #
# Dart emission
# --------------------------------------------------------------------------- #


def dart_literal(value: Any, indent: int) -> str:
    pad = "  " * indent
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return str(int(value)) if value.is_integer() else repr(value)
    if isinstance(value, str):
        escaped = (
            value.replace("\\", "\\\\")
            .replace("'", "\\'")
            .replace("$", "\\$")
            .replace("\n", "\\n")
        )
        return f"'{escaped}'"
    if isinstance(value, list):
        if not value:
            return "<Object?>[]"
        if all(isinstance(item, (int, float)) and not isinstance(item, bool) for item in value):
            joined = ", ".join(dart_literal(item, indent) for item in value)
            return f"<double>[{joined}]"
        items = ",\n".join(f"{pad}  {dart_literal(item, indent + 1)}" for item in value)
        return "<Object?>[\n" + items + f",\n{pad}]"
    if isinstance(value, dict):
        entries = ",\n".join(
            f"{pad}  {dart_literal(key, indent + 1)}: {dart_literal(item, indent + 1)}"
            for key, item in value.items()
        )
        return "<String, Object?>{\n" + entries + f",\n{pad}}}"
    raise TypeError(f"unsupported literal: {value!r}")


def dart_list(name: str, records: list[dict]) -> str:
    if not records:
        return f"  static const List<Map<String, Object?>> {name} = <Map<String, Object?>>[];\n"
    body = ",\n".join(f"    {dart_literal(record, 2)}" for record in records)
    return (
        f"  static const List<Map<String, Object?>> {name} = <Map<String, Object?>>[\n"
        f"{body},\n  ];\n"
    )


# --------------------------------------------------------------------------- #
# sheet readers
# --------------------------------------------------------------------------- #


def build_area_splits(rent_roll: list[dict]) -> dict[str, dict[str, float]]:
    """Sum lettable area per asset, split into residential vs commercial.

    Uses the same commercial classifier as the rent plans so the area split and
    the rent-type split agree.
    """
    result = {"residential": {}, "commercial": {}}
    for row in rent_roll:
        area = row["area"] or 0
        if area <= 0:
            continue
        bucket = "commercial" if _is_commercial(row["unit_code"], row) else "residential"
        result[bucket][row["property_id"]] = (
            result[bucket].get(row["property_id"], 0) + area
        )
    return result


def read_assets(
    wb, area_splits: dict[str, dict[str, float]]
) -> tuple[list[dict], list[dict]]:
    properties: list[dict] = []
    snapshots: list[dict] = []
    for _, values in rows_of(wb["Asset_Master"], 4):
        asset_id = text(cell(values, 0))
        if asset_id is None:
            continue
        raw_type = text(cell(values, 2)) or ""
        raw_status = text(cell(values, 3)) or ""
        app_type = ASSET_TYPE_TO_APP_VALUE.get(raw_type.lower(), "other")
        german_label = ASSET_TYPE_GERMAN_LABEL.get(raw_type.lower(), raw_type)
        living_area = positive(cell(values, 8))
        total_area = positive(cell(values, 9))
        asset_price = positive(cell(values, 12))
        property_price = positive(cell(values, 13))
        renovation_cost = positive(cell(values, 14))
        market_2021 = positive(cell(values, 15))
        market_2026 = positive(cell(values, 16))
        side_costs_yearly = positive(cell(values, 11))

        # Residential vs commercial area. For a mixed object the split matters, so
        # take it from the rent roll (the only sheet that classifies space by
        # use). A single-use object gets the master living area on the matching
        # side, falling back to the rent-roll sum when the master leaves it blank.
        rr_res = area_splits["residential"].get(asset_id)
        rr_com = area_splits["commercial"].get(asset_id)
        if app_type == "mixed":
            res_area, com_area = rr_res, rr_com
        elif app_type in ("residential", "multifamily"):
            res_area, com_area = living_area or rr_res, None
        elif app_type == "commercial":
            res_area, com_area = None, living_area or rr_com
        else:  # hotel, other: rooms/plot, not lettable residential/commercial area
            res_area = com_area = None
        # Land area is the plot; only record it when it genuinely differs from
        # the building's lettable area.
        land_area = total_area if total_area and total_area != living_area else None

        notes = [
            f"Importstatus: {STATUS_LABELS.get(raw_status.lower(), raw_status)}",
            f"Objektart (Workbook): {german_label}",
            f"Objektbezeichnung Workbook: {text(cell(values, 1))}",
        ]
        if property_price is not None:
            notes.append(f"Ankaufspreis Grundstück: {money(property_price)}")
        if renovation_cost is not None:
            notes.append(f"Renovierungskosten bis 2025: {money(renovation_cost)}")
        if side_costs_yearly is not None:
            notes.append(f"Nebenkosten p.a. (Workbook): {money(side_costs_yearly)}")
        notes.append("Quelle: Asset_Overview_v4.xlsx / Asset_Master")

        properties.append(
            {
                "id": asset_id,
                "name": text(cell(values, 1)) or asset_id,
                "property_type": app_type,
                "status": raw_status,
                "address_line1": text(cell(values, 4)) or "",
                "zip": text(cell(values, 5)) or "",
                "city": text(cell(values, 6)) or "",
                "year_built": integer(cell(values, 7)),
                "sqft": rounded(living_area if living_area is not None else total_area),
                "land_area": rounded(land_area),
                "residential_area": rounded(res_area),
                "commercial_area": rounded(com_area),
                "owner_company": PORTFOLIO_OWNER,
                "purchase_price": rounded(asset_price),
                "units": integer(cell(values, 10)) or 0,
                "archived": raw_status.lower() != "active",
                "notes": "\n".join(notes),
            }
        )

        for period, valuation, capex in (
            ("2021-12-31", market_2021, None),
            ("2026-12-31", market_2026, renovation_cost),
        ):
            if valuation is None and capex is None:
                continue
            snapshots.append(
                {
                    "id": f"asset_overview_kpi_{asset_id}_{period[:4]}",
                    "property_id": asset_id,
                    "period_date": period,
                    "valuation": rounded(valuation),
                    "capex": rounded(capex),
                }
            )
    return properties, snapshots


def read_rent_roll(wb) -> list[dict]:
    """Units incl. contract figures; keyed by (asset id, unit code)."""
    units: list[dict] = []
    for _, values in rows_of(wb["Unit_Rent_Roll"], 4):
        asset_id = text(cell(values, 0))
        unit_code = text(cell(values, 2))
        if asset_id is None or unit_code is None:
            continue
        tenants = [
            name
            for name in (text(cell(values, index)) for index in (6, 7, 8))
            if name is not None
        ]
        status = (text(cell(values, 4)) or "").lower()
        units.append(
            {
                "property_id": asset_id,
                "unit_code": unit_code,
                "status": "occupied" if status == "rented" else "vacant",
                "tenants": tenants,
                "tenant_display": text(cell(values, 5)),
                "contract_cold": rounded(number(cell(values, 11))),
                "contract_warm": rounded(number(cell(values, 12))),
                "contract_side": rounded(number(cell(values, 13))),
                "contract_heating": rounded(number(cell(values, 14))),
                "contract_tax": rounded(number(cell(values, 15))),
                "market_cold": rounded(number(cell(values, 17))),
                "market_side": rounded(number(cell(values, 18))),
                "market_heating": rounded(number(cell(values, 19))),
                "market_tax": rounded(number(cell(values, 20))),
                "market_warm": rounded(number(cell(values, 21))),
                "last_rent_change": iso_date(cell(values, 22)),
                "area": rounded(positive(cell(values, 23))),
                "target_per_sqm": rounded(positive(cell(values, 24))),
                "allocation_key": number(cell(values, 25)),
                "addition": text(cell(values, 26)),
                "addition_cost": rounded(positive(cell(values, 27))),
                "opportunity_cost": rounded(number(cell(values, 28))),
            }
        )
    return units


def read_rent_information(wb) -> dict[tuple[str, str], dict]:
    """Deposits and rent-adjustment rules, keyed by (asset id, unit code)."""
    result: dict[tuple[str, str], dict] = {}
    for _, values in rows_of(wb["Rent_Information"], 3):
        asset_id = text(cell(values, 0))
        unit_code = text(cell(values, 2))
        if asset_id is None or unit_code is None:
            continue
        result[(asset_id, normalise(unit_code))] = {
            "raise_percent": number(cell(values, 5)),
            "raise_amount": positive(cell(values, 6)),
            "raise_every_months": integer(cell(values, 7)),
            "raise_timeframe_months": integer(cell(values, 8)),
            "raise_date": iso_date(cell(values, 9)),
            "new_cold_rent": positive(cell(values, 10)),
            "deposit_target": positive(cell(values, 12)),
            "deposit_agreed": positive(cell(values, 13)),
            "deposit_paid": (text(cell(values, 20)) or "N").upper() == "Y",
        }
    return result


def read_payments(wb) -> dict[tuple[str, str], dict]:
    """Aggregate the 2026 payment sheet per unit (rows can be per co-tenant)."""
    result: dict[tuple[str, str], dict] = {}
    seen: set[str] = set()
    for _, values in rows_of(wb["Rent_Payments_2026"], 6):
        name = text(cell(values, 0))
        if name is None:
            continue
        key = normalise(name)
        seen.add(key)
        target = PAYMENT_ROW_TO_UNIT.get(key)
        if target is None:
            if key not in PAYMENT_ROWS_WITHOUT_UNIT:
                raise SystemExit(
                    f"Rent_Payments_2026: no unit mapping for tenant row {name!r}. "
                    "Extend PAYMENT_ROW_TO_UNIT or PAYMENT_ROWS_WITHOUT_UNIT."
                )
            continue
        entry = result.setdefault(
            target,
            {"months": [0.0] * 12, "deposit": None, "start_date": None, "rent_amount": 0.0},
        )
        # Columns H..O carry 2026-05 .. 2026-12.
        for offset in range(8):
            amount = positive(cell(values, 7 + offset))
            if amount is not None:
                entry["months"][4 + offset] += amount
        rent = positive(cell(values, 6))
        if rent is not None:
            entry["rent_amount"] += rent
        deposit = positive(cell(values, 5))
        if deposit is not None:
            entry["deposit"] = (entry["deposit"] or 0.0) + deposit
        start = iso_date(cell(values, 3))
        if start is not None:
            entry["start_date"] = start

    unmatched = PAYMENT_ROWS_WITHOUT_UNIT - seen
    if unmatched:
        raise SystemExit(f"Rent_Payments_2026: expected placeholder rows missing: {unmatched}")
    return result


def read_utility_contracts(wb) -> dict[str, dict]:
    """Contract metadata keyed by contract number (as printed on the invoice)."""
    contracts: dict[str, dict] = {}
    for _, values in rows_of(wb["Utility_Contracts"], 4):
        utility_type = text(cell(values, 0))
        contract_no = integer(positive(cell(values, 1)))
        asset_id = text(cell(values, 15))
        if utility_type not in UTILITY_TYPE_LABELS or contract_no is None or asset_id is None:
            continue
        contracts[str(contract_no)] = {
            "utility_type": UTILITY_TYPE_LABELS[utility_type],
            "subject": text(cell(values, 2)),
            "advance_payment": positive(cell(values, 3)),
            "start_date": iso_date(cell(values, 5)),
            "last_billing": iso_date(cell(values, 7)),
            "binding_until": iso_date(cell(values, 9)),
            "provider": text(cell(values, 11)),
            "invoice_unit": text(cell(values, 13)),
            "asset_id": asset_id,
        }
    return contracts


def read_unit_costs(wb, contracts: dict[str, dict]) -> list[dict]:
    """One operating-cost record per metered utility per unit."""
    costs: list[dict] = []
    counter = 0
    specs = [
        ("Strom", 4, 5, 6, 8, 7, None),
        ("Wasser", 10, 11, 12, 14, 13, None),
        ("Heizung", 16, 17, 18, 22, 21, 19),
    ]
    for _, values in rows_of(wb["Unit_Side_Costs"], 4):
        asset_id = text(cell(values, 0))
        if asset_id is None:
            continue
        unit_code = text(cell(values, 2))
        for label, contract_col, meter_col, cancel_col, monthly_col, yearly_col, type_col in specs:
            contract_no = integer(positive(cell(values, contract_col)))
            meter = text(cell(values, meter_col))
            monthly = positive(cell(values, monthly_col))
            yearly = positive(cell(values, yearly_col))
            canceled = (text(cell(values, cancel_col)) or "").lower().startswith("cancel")
            if contract_no is None and meter is None and monthly is None and not canceled:
                continue

            contract = contracts.get(str(contract_no)) if contract_no is not None else None
            notes = []
            if meter is not None:
                notes.append(f"Zähler: {meter}")
            if type_col is not None:
                heating_type = text(cell(values, type_col))
                if heating_type is not None and not heating_type.lower().startswith("cancel"):
                    notes.append(f"Heizart: {heating_type}")
            if contract is not None:
                if contract["subject"] is not None:
                    notes.append(f"Tarif: {contract['subject']}")
                if contract["invoice_unit"] is not None:
                    notes.append(f"Abrechnungseinheit: {contract['invoice_unit']}")
                if contract["last_billing"] is not None:
                    notes.append(f"Letzte Abrechnung: {contract['last_billing']}")
            if canceled:
                notes.append("Vertrag durch Mieter gekündigt")
            notes.append("Quelle: Asset_Overview_v4.xlsx / Unit_Side_Costs")

            counter += 1
            costs.append(
                {
                    "id": f"asset_overview_cost_unit_{counter:03d}",
                    "property_id": asset_id,
                    "scope": "unit",
                    "unit_code": None if unit_code in (None, "House") else unit_code,
                    "cost_type": label,
                    "provider": (contract or {}).get("provider"),
                    "contract_number": None if contract_no is None else str(contract_no),
                    "allocation_key": None,
                    "monthly_amount": rounded(monthly),
                    "yearly_amount": rounded(yearly if yearly is not None else (monthly * 12 if monthly else None)),
                    "canceled": canceled,
                    "start_date": (contract or {}).get("start_date"),
                    "end_date": None,
                    "next_due_date": (contract or {}).get("binding_until"),
                    "notes": "\n".join(notes),
                }
            )
    return costs


def read_building_costs(wb) -> list[dict]:
    costs: list[dict] = []
    counter = 0
    for _, values in rows_of(wb["Building_Side_Costs"], 4):
        asset_id = text(cell(values, 0))
        if asset_id is None:
            continue
        for column, label in BUILDING_COST_COLUMNS:
            yearly = positive(cell(values, column))
            if yearly is None:
                continue
            counter += 1
            costs.append(
                {
                    "id": f"asset_overview_cost_building_{counter:03d}",
                    "property_id": asset_id,
                    "scope": "building",
                    "unit_code": None,
                    "cost_type": label,
                    "provider": None,
                    "contract_number": None,
                    "allocation_key": "Wohnfläche",
                    "monthly_amount": rounded(yearly / 12),
                    "yearly_amount": rounded(yearly),
                    "canceled": False,
                    "start_date": None,
                    "end_date": None,
                    "next_due_date": None,
                    "notes": "Umlagefähig. Quelle: Asset_Overview_v4.xlsx / Building_Side_Costs",
                }
            )
    return costs


def read_insurance_costs(wb) -> list[dict]:
    costs: list[dict] = []
    counter = 0
    for _, values in rows_of(wb["Insurance_Master"], 4):
        asset_id = text(cell(values, 0))
        raw_type = text(cell(values, 2))
        yearly = positive(cell(values, 3))
        if asset_id is None or raw_type is None or yearly is None:
            continue
        quarterly = positive(cell(values, 4))
        notes = ["Quelle: Asset_Overview_v4.xlsx / Insurance_Master"]
        if quarterly is not None:
            notes.insert(0, f"Quartalsbeitrag: {money(quarterly)}")
        counter += 1
        costs.append(
            {
                "id": f"asset_overview_cost_insurance_{counter:03d}",
                "property_id": asset_id,
                "scope": "insurance",
                "unit_code": None,
                "cost_type": INSURANCE_TYPE_LABELS.get(raw_type.lower(), raw_type),
                "provider": None,
                "contract_number": None,
                "allocation_key": "Wohnfläche",
                "monthly_amount": rounded(yearly / 12),
                "yearly_amount": rounded(yearly),
                "canceled": False,
                "start_date": None,
                "end_date": None,
                "next_due_date": None,
                "notes": "\n".join(notes),
            }
        )
    return costs


def read_hotel_costs(wb) -> dict[tuple[str, str], str]:
    """Monthly hotel cost breakdown as a note per (asset id, period)."""
    notes: dict[tuple[str, str], str] = {}
    for _, values in rows_of(wb["Hotel_Costs"], 4):
        asset_id = text(cell(values, 0))
        period = text(cell(values, 2))
        if asset_id is None or period is None:
            continue
        parts = []
        for column, label in HOTEL_COST_COLUMNS:
            amount = positive(cell(values, column))
            if amount is not None:
                parts.append(f"{label} {money(amount)}")
        if parts:
            notes[(asset_id, period)] = "Kostenaufteilung: " + "; ".join(parts)
    return notes


def read_hotel_kpis(wb, cost_notes: dict[tuple[str, str], str]) -> list[dict]:
    records: list[dict] = []
    for _, values in rows_of(wb["Hotel_KPIs"], 4):
        asset_id = text(cell(values, 0))
        period = text(cell(values, 2))
        if asset_id is None or period is None or period not in MONTHS:
            continue
        month_index = MONTHS.index(period) + 1
        rooms_total = integer(cell(values, 3))
        rooms_available = integer(cell(values, 4))
        rooms_occupied = integer(cell(values, 5))
        adr = positive(cell(values, 7))
        revpar = positive(cell(values, 8))
        fb_revenue = positive(cell(values, 9))
        room_revenue = positive(cell(values, 10))
        other_revenue = positive(cell(values, 11))
        total_revenue = positive(cell(values, 12))
        total_costs = positive(cell(values, 13))
        profit = number(cell(values, 14))
        gop = number(cell(values, 15))
        comment = text(cell(values, 16))

        has_data = any(
            value is not None
            for value in (
                rooms_total,
                rooms_available,
                rooms_occupied,
                adr,
                revpar,
                fb_revenue,
                room_revenue,
                other_revenue,
                total_revenue,
                total_costs,
            )
        )
        if not has_data:
            continue

        # Revenue, costs and profit are structured columns now; notes only carry
        # the supplementary cost breakdown and any free-text comment.
        notes = []
        if other_revenue is not None:
            notes.append(f"Sonstige Erlöse / Miete {money(other_revenue)}")
        breakdown = cost_notes.get((asset_id, period))
        if breakdown is not None:
            notes.append(breakdown)
        if comment is not None:
            notes.append(comment)
        notes.append("Quelle: Asset_Overview_v4.xlsx / Hotel_KPIs + Hotel_Costs")

        # profit/loss = revenue − costs; take the workbook's figure when present,
        # otherwise derive it so the P&L always reconciles.
        profit_loss = profit
        if profit_loss is None and total_revenue is not None and total_costs is not None:
            profit_loss = total_revenue - total_costs

        records.append(
            {
                "id": f"asset_overview_hotel_{asset_id}_2026_{month_index:02d}",
                "property_id": asset_id,
                "period_key": f"2026-{month_index:02d}",
                "rooms_total": rooms_total,
                "rooms_available": rooms_available,
                "rooms_occupied": rooms_occupied,
                "adr": rounded(adr),
                "revpar": rounded(revpar),
                "fb_revenue": rounded(fb_revenue),
                "room_revenue": rounded(room_revenue),
                "total_revenue": rounded(total_revenue),
                "total_costs": rounded(total_costs),
                "profit_loss": rounded(profit_loss),
                "gop_percent": rounded(None if gop is None else gop * 100),
                "notes": " | ".join(notes),
            }
        )
    return records


def read_renovations(wb) -> list[dict]:
    records: list[dict] = []
    for _, values in rows_of(wb["Renovations_EN"], 4):
        project_code = text(cell(values, 0))
        asset_id = text(cell(values, 1))
        if project_code is None or asset_id is None:
            continue
        raw_category = text(cell(values, 3)) or ""
        raw_status = text(cell(values, 5)) or "Planned"
        records.append(
            {
                "id": f"asset_overview_reno_{project_code}",
                "property_id": asset_id,
                "project_code": project_code,
                "category": RENOVATION_CATEGORY_LABELS.get(raw_category.lower(), raw_category or None),
                "measure": text(cell(values, 4)),
                "status": RENOVATION_STATUS_LABELS.get(raw_status.lower(), raw_status),
                "start_date": iso_date(cell(values, 6)),
                "planned_end_date": iso_date(cell(values, 7)),
                "actual_end_date": iso_date(cell(values, 8)),
                "budget_amount": rounded(positive(cell(values, 9))),
                "actual_amount": rounded(positive(cell(values, 10))),
                "owner": text(cell(values, 12)),
                "next_step": text(cell(values, 13)),
            }
        )
    return records


# --------------------------------------------------------------------------- #
# derived records
# --------------------------------------------------------------------------- #


def build_units_tenants_leases(
    rent_roll: list[dict],
    rent_info: dict[tuple[str, str], dict],
    payments: dict[tuple[str, str], dict],
) -> tuple[list[dict], list[dict], list[dict], list[dict]]:
    units: list[dict] = []
    tenants: list[dict] = []
    leases: list[dict] = []
    plans: list[dict] = []
    tenant_ids: dict[str, str] = {}

    for index, row in enumerate(rent_roll, start=1):
        asset_id = row["property_id"]
        unit_code = row["unit_code"]
        unit_id = f"asset_overview_unit_{index:03d}"
        info = rent_info.get((asset_id, normalise(unit_code)), {})
        payment = payments.get((asset_id, unit_code))

        unit_notes = [f"Warmmiete Vertrag: {money(row['contract_warm'] or 0)}"]
        # market_rent_monthly only holds the calculated cold rent, so keep the
        # rest of the workbook's potential-rent breakdown alongside it.
        if row["market_warm"]:
            unit_notes.append(
                f"Potenzial Warmmiete: {money(row['market_warm'])} "
                f"(NK {money(row['market_side'] or 0)} | "
                f"Heizung {money(row['market_heating'] or 0)} | "
                f"Steuer/Umlage {money(row['market_tax'] or 0)})"
            )
        if row["target_per_sqm"] is not None:
            unit_notes.append(f"Zielmiete: {money(row['target_per_sqm'], '€/m²')}")
        if row["allocation_key"]:
            unit_notes.append(f"Umlageschlüssel: {row['allocation_key']:.6f}")
        if row["addition"] is not None:
            cost = row["addition_cost"]
            suffix = f" ({money(cost)})" if cost is not None else ""
            unit_notes.append(f"Zusatz: {row['addition']}{suffix}")
        if row["opportunity_cost"]:
            unit_notes.append(f"Opportunitätskosten: {money(row['opportunity_cost'])}")
        unit_notes.append("Quelle: Asset_Overview_v4.xlsx / Unit_Rent_Roll")

        units.append(
            {
                "id": unit_id,
                "property_id": asset_id,
                "unit_code": unit_code,
                "status": row["status"],
                "sqft": row["area"],
                "market_rent_monthly": row["market_cold"],
                "notes": "\n".join(unit_notes),
            }
        )

        if row["status"] == "occupied" and row["tenants"]:
            for name in row["tenants"]:
                if name not in tenant_ids:
                    tenant_ids[name] = f"asset_overview_tenant_{len(tenant_ids) + 1:03d}"
                    tenants.append({"id": tenant_ids[name], "display_name": name})

            side = row["contract_side"] or 0
            # Warm rent = cold + ancillary + heating/other, so heating and the
            # tax/levy share go into the "other charges" column together.
            other_charges = (row["contract_heating"] or 0) + (row["contract_tax"] or 0)
            lease_notes = [
                f"Nebenkosten: {money(side)} | Heizung: {money(row['contract_heating'] or 0)} | "
                f"Steuer/Umlage: {money(row['contract_tax'] or 0)}",
                f"Warmmiete: {money(row['contract_warm'] or 0)}",
            ]
            if len(row["tenants"]) > 1:
                lease_notes.append("Mietergemeinschaft: " + ", ".join(row["tenants"]))
            if info.get("raise_date") is not None:
                percent = info.get("raise_percent")
                amount = info.get("raise_amount")
                new_rent = info.get("new_cold_rent")
                parts = [f"Mietanpassung zum {info['raise_date']}"]
                if percent is not None:
                    parts.append(f"{percent * 100:.2f} %".replace(".", ","))
                if amount is not None:
                    parts.append(f"+{money(amount)}")
                if new_rent is not None:
                    parts.append(f"neue Kaltmiete {money(new_rent)}")
                if info.get("raise_every_months"):
                    parts.append(f"alle {info['raise_every_months']} Monate")
                lease_notes.append(" | ".join(parts))

            # The workbook tracks a calculated deposit target and, separately,
            # the amount actually agreed with the tenant. Prefer the agreed one.
            deposit_agreed = info.get("deposit_agreed")
            deposit_target = info.get("deposit_target")
            deposit = deposit_agreed
            if deposit is None and payment is not None:
                deposit = payment.get("deposit")
            if deposit is None:
                deposit = deposit_target
            if deposit_target is not None:
                lease_notes.append(
                    f"Kaution Soll: {money(deposit_target)}"
                    + (f" | vereinbart: {money(deposit_agreed)}" if deposit_agreed is not None else "")
                )
            if row["last_rent_change"] is not None:
                lease_notes.append(f"Letzte Mietänderung: {row['last_rent_change']}")
            lease_notes.append("Quelle: Asset_Overview_v4.xlsx / Unit_Rent_Roll + Rent_Information")

            leases.append(
                {
                    "id": f"asset_overview_lease_{index:03d}",
                    "property_id": asset_id,
                    "unit_id": unit_id,
                    "tenant_id": tenant_ids[row["tenants"][0]],
                    "lease_name": f"{unit_code} — {row['tenant_display'] or row['tenants'][0]}",
                    "start_date": (payment or {}).get("start_date"),
                    "status": "active",
                    "base_rent_monthly": row["contract_cold"] or 0.0,
                    "ancillary_charges_monthly": rounded(side) or 0.0,
                    "parking_other_charges_monthly": rounded(other_charges) or 0.0,
                    "security_deposit": rounded(deposit),
                    "deposit_status": "paid" if info.get("deposit_paid") else "open",
                    "notes": "\n".join(lease_notes),
                }
            )

        months = (payment or {}).get("months", [0.0] * 12)
        plan_notes = []
        if payment is None:
            plan_notes.append("Keine Zahlungszeile im Sheet Rent_Payments_2026")
        if row["status"] != "occupied":
            plan_notes.append("Einheit leerstehend")
        plan_notes.append("Quelle: Asset_Overview_v4.xlsx / Rent_Payments_2026")

        plans.append(
            {
                "id": f"asset_overview_rent_{index:03d}",
                "property_id": asset_id,
                "year": 2026,
                "unit_code": unit_code,
                "tenant_name": row["tenant_display"],
                "rent_type": "Kommerziell" if _is_commercial(unit_code, row) else "Privat",
                "target_rent_monthly": row["contract_warm"] or row["market_cold"],
                "side_costs_monthly": rounded((row["contract_side"] or 0) + (row["contract_heating"] or 0)),
                "months": [rounded(value) or 0.0 for value in months],
                "status_note": " | ".join(plan_notes),
            }
        )

    return units, tenants, leases, plans


def _is_commercial(unit_code: str, row: dict) -> bool:
    haystack = f"{unit_code} {row['tenant_display'] or ''}".lower()
    keywords = ("gewerbe", "kiosk", "bäckerei", "bakery", "pizzeria", "wettbüro", "eg left", "monkeys")
    return any(keyword in haystack for keyword in keywords)


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    workbook_path = pathlib.Path(sys.argv[1])
    if not workbook_path.is_file():
        print(f"workbook not found: {workbook_path}", file=sys.stderr)
        return 2

    digest = hashlib.sha256(workbook_path.read_bytes()).hexdigest()
    wb = openpyxl.load_workbook(workbook_path, data_only=True)

    rent_roll = read_rent_roll(wb)
    properties, snapshots = read_assets(wb, build_area_splits(rent_roll))
    rent_info = read_rent_information(wb)
    payments = read_payments(wb)
    contracts = read_utility_contracts(wb)

    units, tenants, leases, plans = build_units_tenants_leases(rent_roll, rent_info, payments)
    costs = read_unit_costs(wb, contracts) + read_building_costs(wb) + read_insurance_costs(wb)
    hotel_kpis = read_hotel_kpis(wb, read_hotel_costs(wb))
    renovations = read_renovations(wb)

    # Hidden helper sheets still carry rows for assets that v4 retired. Drop
    # those quietly, but fail loudly on any other unknown asset id so a new
    # workbook revision cannot silently lose data.
    known_ids = {record["id"] for record in properties}
    for name, records in (
        ("units", units),
        ("leases", leases),
        ("rentalPlans", plans),
        ("operatingCosts", costs),
        ("hotelKpis", hotel_kpis),
        ("renovations", renovations),
        ("valuationSnapshots", snapshots),
    ):
        orphans = {record["property_id"] for record in records} - known_ids
        unexpected = orphans - set(RETIRED_PROPERTY_IDS)
        if unexpected:
            raise SystemExit(f"{name}: rows reference unknown assets {sorted(unexpected)}")
        if orphans:
            dropped = [record for record in records if record["property_id"] in orphans]
            records[:] = [record for record in records if record["property_id"] not in orphans]
            print(f"  dropped {len(dropped)} {name} row(s) for retired assets {sorted(orphans)}")

    body = [
        "// GENERATED FILE — DO NOT EDIT BY HAND.",
        "//",
        f"// Source workbook: {workbook_path.name}",
        f"// SHA-256: {digest}",
        "// Regenerate with: python tool/generate_asset_overview_seed.py <workbook.xlsx>",
        "//",
        "// Dates are ISO-8601 strings and are converted to epoch millis by the",
        "// migration that consumes this data.",
        "",
        "/// Portfolio baseline extracted from the Asset Overview workbook.",
        "class AssetOverviewSeedData {",
        "  const AssetOverviewSeedData._();",
        "",
        "  /// Asset ids seeded by earlier workbook revisions that v4 dropped.",
        "  static const List<String> retiredPropertyIds = <String>[",
        *[f"    '{asset_id}'," for asset_id in RETIRED_PROPERTY_IDS],
        "  ];",
        "",
        "  /// Prefix shared by every row this seed owns, used to purge stale data.",
        "  static const String rowIdPrefix = 'asset_overview_';",
        "",
    ]
    body.append(dart_list("properties", properties))
    body.append(dart_list("valuationSnapshots", snapshots))
    body.append(dart_list("units", units))
    body.append(dart_list("tenants", tenants))
    body.append(dart_list("leases", leases))
    body.append(dart_list("rentalPlans", plans))
    body.append(dart_list("operatingCosts", costs))
    body.append(dart_list("hotelKpis", hotel_kpis))
    body.append(dart_list("renovations", renovations))
    body.append("}")
    body.append("")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(body), encoding="utf-8")

    print(f"wrote {OUT_PATH.relative_to(REPO_ROOT)}")
    for label, records in (
        ("properties", properties),
        ("valuation snapshots", snapshots),
        ("units", units),
        ("tenants", tenants),
        ("leases", leases),
        ("rental plans", plans),
        ("operating costs", costs),
        ("hotel kpis", hotel_kpis),
        ("renovations", renovations),
    ):
        print(f"  {label}: {len(records)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
