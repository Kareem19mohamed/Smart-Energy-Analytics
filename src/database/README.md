# Database Documentation - ElectricityDB

## 1. Schema Overview
Database: `ElectricityDB`
Consists of two relational tables implementing a One-to-Many (1:N) relationship with a Composite Primary Key.

```
[dbo.Households] (Parent)
    │ PK: household_id
    │
    └─── 1 : Many
         │
         ▼
[dbo.ElectricityReadings] (Child)
    PK: (household_id, reading_time)
    FK: household_id REFERENCES dbo.Households(household_id)
```

---

## 2. Table Definitions & Data Dictionary

### A. Parent Table: `dbo.Households`
| Column Name | Data Type | Constraint | Description |
|---|---|---|---|
| `household_id` | `VARCHAR(20)` | PRIMARY KEY | Unique household identifier (`House_01`, `House_03`, `House_04`) |
| `source_file` | `VARCHAR(100)` | NOT NULL | Source CSV filename |
| `description` | `NVARCHAR(255)` | NULL | Household description |
| `created_at` | `DATETIME2` | DEFAULT SYSDATETIME() | Record timestamp |

### B. Child Table: `dbo.ElectricityReadings`
Stores 15-minute smart meter readings (119,375 total records).

| Column Name | Data Type | Constraint | Description |
|---|---|---|---|
| `household_id` | `VARCHAR(20)` | PK, FK | Foreign key to Households table |
| `reading_time` | `DATETIME2(0)` | PK | Timestamp of reading (Composite PK with household_id) |
| `V` | `FLOAT` | NULL | Voltage (Volts) |
| `A` | `FLOAT` | NULL | Current (Amperes) |
| `P_agg` | `FLOAT` | NULL | Active aggregate power (Watts) |
| `ac_1` | `FLOAT` | NULL | AC Unit 1 power (Watts) |
| `ac_2` | `FLOAT` | NULL | AC Unit 2 power (Watts) |
| `boiler` | `FLOAT` | NULL | Water boiler power (Watts) |
| `fridge` | `FLOAT` | NULL | Refrigerator power (Watts) |
| `washing_machine` | `FLOAT` | NULL | Washing machine power (Watts) |
| `issues` | `FLOAT` | NULL | Data quality metric score |
| `internal_temperature` | `FLOAT` | NULL | Indoor temperature (°C) |
| `internal_humidity` | `FLOAT` | NULL | Indoor relative humidity (%) |
| `external_temperature` | `FLOAT` | NULL | Outdoor temperature (°C) |
| `external_humidity` | `FLOAT` | NULL | Outdoor relative humidity (%) |

---

## 3. Relationships & Constraints
1. **Composite Primary Key:** `PK_ElectricityReadings (household_id, reading_time)` ensures zero duplicate readings per house.
2. **Foreign Key:** `FK_Readings_Households` enforces referential integrity.
3. **Indexes:**
   - `IX_Readings_Time`: Clustered/Non-clustered temporal index on `reading_time`.
   - `IX_Readings_Household_Time`: Covering index on `(household_id, reading_time)`.
