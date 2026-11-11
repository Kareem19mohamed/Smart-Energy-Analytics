# Smart Energy Analytics

A data analytics and forecasting platform for residential energy consumption and environmental conditions across multiple households. Developed as a graduation capstone project under the **Digital Egypt Pioneers Initiative (DEPI)**.

---

## 📌 Project Overview

This project provides an automated end-to-end data pipeline that ingests high-frequency smart meter electrical readings along with environmental/weather sensor datasets, harmonizes their temporal resolutions, and produces clean, unified time-series datasets ready for machine learning forecasting and interactive dashboards.

---

## 🏗️ Architecture & Pipeline Design

```
Raw Data (Target Houses)
 │
 ├── house_X/Electric_data/
 │    └── [Monthly CSVs] ──► Exclude Metadata ──► Convert Datetime ──► Resample (15m, mean) ──► Concat
 │                                                                                               │
 └── house_X/Environmental_data/                                                                 ▼
      └── [Monthly CSVs] ──► Exclude Metadata ──► Convert Datetime ──► Set Index ─────────────► Inner Join
                                                                                                 │
                                                                                                 ▼
                                                                           data/processed/<house_X>.csv
```

### Key Engineering Decisions:
1. **Per-Month Resampling**:
   - Electrical sensor readings are resampled to a consistent 15-minute frequency **prior to monthly concatenation**. This prevents edge-boundary averaging distortion if a given month starts or ends with gaps.
2. **Deterministic & Safe Ingestion**:
   - Files are discovered and sorted deterministically across platforms using `pathlib.Path`.
   - Metadata files (`*metadata*`) containing house specifications are automatically filtered out during ingestion to avoid schema collisions.
3. **Temporal Alignment**:
   - Both datasets are aligned on their `pd.DatetimeIndex` via an inner join, creating a strictly synchronized feature set for predictive modeling.

---

## 📁 Repository Structure

```text
Smart-Energy-Analytics/
├── data/
│   ├── raw/                 # Placeholder for raw datasets
│   └── processed/           # Processed per-house CSV outputs (.gitignore protected)
├── src/
│   ├── data_processing/
│   │   ├── __init__.py
│   │   ├── data_ingestion.py       # File discovery, exclusion & reading
│   │   ├── data_transformation.py  # Resampling & temporal aggregation logic
│   │   └── clean_data.py           # Anomaly detection & cleaning stubs
│   ├── models/
│   │   └── forecasting.py          # Predictive modeling & load forecasting
│   └── dashboard/
│       └── app.py                  # Visualization application
├── main.py                  # Pipeline execution entry point
├── requirements.txt         # Core dependencies
├── .gitignore               # Git exclusion rules
└── README.md                # Project documentation
```

---

## 🚀 Getting Started

### 1. Prerequisites
- Python 3.10+ (tested with Python 3.13)
- Git

### 2. Installation
Clone the repository and install required dependencies:

```bash
git clone https://github.com/your-username/Smart-Energy-Analytics.git
cd Smart-Energy-Analytics
pip install -r requirements.txt
```

### 3. Configuration
Ensure your raw house folders follow the expected layout:
```text
target_houses/
├── house_1/
│   ├── Electric_data/
│   │   ├── 2023_01.csv
│   │   └── ...
│   └── Environmental_data/
│       ├── 2023_01.csv
│       └── ...
```
Adjust the `root_dir` variable in `main.py` if your dataset path differs.

### 4. Running the Pipeline
Execute the full preprocessing pipeline:

```bash
python main.py
```

The processed, synchronized datasets will be exported to `data/processed/<house_name>.csv`.

---

## 🛠️ Tech Stack
- **Language**: Python 3
- **Data Engineering**: Pandas, Pathlib
- **Storage**: CSV / Excel
- **Analytics & Visualization**: Matplotlib / Streamlit *(planned)*
- **Machine Learning**: Scikit-Learn / Statsmodels *(planned)*
