# Design Doc: Open Tender Watch (Rails + Hotwire)

## Overview
A web application for the automated crossing of Portuguese public databases to detect irregularities in public procurement.

## UX Principles
- **Atmosphere:** Cyberpunk-noir, dark mode, high contrast, "Live" system feeling.
- **Visuals:** Grid overlays, scanline effects, monospaced fonts for data, animated progress/score bars, rounded square backgrounds avoided for icons - geometric icons preferred.
- **Interaction:** Fast transitions, expanded detail views for insights, tabbed navigation.

## Page Structure (Main Dashboard)

### 1. Header
- **Status Indicator:** "LIVE" with pulsing red dot.
- **Prototype Badge:** Indicating CSV/Manual data source.
- **Title:** "Open Tender Watch" with a gradient effect.
- **Subtitle:** Description of the tool's purpose.

### 2. Global Stats Bar
- Grid-based summary of:
    - **ENTIDADES** (Count of unique entities)
    - **CONEXÕES** (Count of identified links)
    - **FONTES** (Count of data sources)
    - **ALERTAS** (Count of critical/high severity items)

### 3. Navigation Tabs
- **Insights:** The primary feed of identified patterns.
- **Cruzamentos (Crossings):** Overview of how NIF/NIPC links different datasets.
- **Fontes (Sources):** Status and record counts of the connected databases (Portal BASE, ECFP, etc.).

### 4. Insights Tab Content
- **Exposição Total (Total Exposure):** Large display of the monetary value under scrutiny.
- **Filters:** Buttons to filter by severity (Todos, Crítico, Alto, Médio).
- **Insight Cards:**
    - **Header:** Severity badge, Subtitle (Location/Entity), Score bar.
    - **Body:** Title, Amount (with 💰 icon).
    - **Expanded Detail:**
        - Description paragraph.
        - Pattern box (Technical summary of the logic).
        - Source tags.

### 5. Crossings Tab Content
- Table-like view showing the count of entities identified across different source combinations.
- Visual ASCII/Code-style diagram showing the NIF/NIPC link architecture.

### 6. Sources Tab Content
- Cards for each source showing:
    - Name and Type.
    - Status (Online, Partial, Restricted) with colored status light.
    - Total record count.

## Technical Implementation (Rails 8)
- **CSS:** Tailwind CSS with custom colors (`#0d0f14` background, `#c8a84e` gold, `#ff4444` red).
- **Icons:** Inline SVGs or Lucide icons.
- **Dynamic UI:** Hotwire (Turbo Frames for tabs, Stimulus for card expansion and animations).
- **Animations:** CSS keyframes for `fadeUp`, `pulse`, and `scanline`.
