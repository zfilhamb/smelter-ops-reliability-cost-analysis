# Insight Operasional, Downtime & Cost
## PT Nusa Tembaga Smelting (data sintetis) — Januari 2025 – Agustus 2026

Disusun oleh Zulfikar, berdasarkan analisis tiga dashboard: Operations & PPC, Downtime & Reliability, dan Cost & Budget. Seluruh angka pada dokumen ini berasal dari dataset sintetis untuk tujuan portofolio, bukan data operasional perusahaan sungguhan.

## Ringkasan Eksekutif

Operasional harian relatif terkendali — di luar satu event besar, pengeluaran bulanan cenderung sesuai budget. Titik kebocoran waktu dan biaya terkonsentrasi di dua tempat spesifik: **keandalan lima equipment kritis** (77,3% dari seluruh downtime tak terencana) dan **manajemen kontraktor saat turnaround** (overrun $1,56 juta, atau 36,4% di atas budget).

| Indikator | Nilai |
|---|---|
| Downtime terkonsentrasi di | 5 dari 14 equipment (77,3%) |
| Overrun turnaround FSF | 48 jam (+14,3% dari rencana) |
| Overrun biaya bulan turnaround | +$1,78 juta (+16,1%) |
| Cost per ton cathode, 2025 → 2026 | $471,8 → $465,6 (−1,3%, stabil/membaik) |

## 1. Downtime & Reliability

### Pareto — 5 equipment menyumbang 77,3% downtime tak terencana

| Equipment | Lost hours (equiv) | Kumulatif |
|---|---|---|
| Flash Smelting Furnace | 149,5 | 24,3% |
| Acid Plant | 110,4 | 42,3% |
| Concentrate Dryer | 102,1 | 58,9% |
| Oxygen Plant | 84,1 | 72,6% |
| Anode Furnace | 28,8 | 77,3% |

Sisa 9 equipment lain hanya menyumbang 22,7% dari total downtime — prioritas maintenance 2027 seharusnya difokuskan ke 5 equipment di atas, bukan disebar rata.

### Dua pola kegagalan yang berbeda, butuh solusi berbeda

**Concentrate Dryer — sering gagal, cepat diperbaiki**
19 kegagalan dalam periode data, MTBF 761 jam (terendah dari top 5), MTTR 7,4 jam. Masalahnya ada di *frekuensi/kualitas komponen* — solusinya inspeksi rutin lebih sering.

**Acid Plant — jarang gagal, tapi lama diperbaiki**
11 kegagalan, MTBF 1.309 jam (paling jarang dari top 5), MTTR 17,7 jam — **paling lama dari seluruh equipment**. Masalahnya ada di *kesiapan tim/spare part saat insiden* — solusinya SOP darurat dan stok spare part kritis, bukan menambah inspeksi.

### Turnaround Flash Smelting Furnace, Oktober 2025

Direncanakan 14 hari, berjalan 16 hari — overrun 48 jam (+14,3%). Dampak biayanya jauh lebih besar dari proporsi waktunya (lihat bagian Cost & Budget).

## 2. Cost & Budget

### Turnaround Oktober 2025 adalah satu-satunya sumber overrun signifikan

Bulan ini overrun $1.775.351 (+16,1%) — **lebih besar dari total net overrun seluruh periode lain digabung** ($1,70 juta net across 20 bulan). Artinya: di luar bulan turnaround ini, operasional bulanan sebenarnya cukup disiplin terhadap budget.

Penyebab utamanya jelas: **Contractors & Services overrun +36,4% ($1.558.684)** — jauh di atas Refractory & Spares yang cuma +12,5% ($404.242). Ini sendirian hampir sama besar dengan total overrun turnaround.

### Overrun per cost center (seluruh periode, 20 bulan closed)

| Cost Center | Variance | Variance % |
|---|---|---|
| Plant Maintenance | +$1.450.796 | +6,8% |
| Environment, Health & Safety | +$124.621 | +2,5% |
| Oxygen & Utilities | +$98.651 | +0,8% |
| Smelting (FSF/FCF) | +$242.142 | +0,6% |
| Acid Plant | +$70.623 | +0,6% |
| Anode Refining & Casting | +$32.478 | +0,2% |
| Concentrate Handling & Drying | −$8.213 | −0,1% |
| Electrorefinery | −$311.343 | −1,1% |

Plant Maintenance menyumbang 85% dari total net overrun — ini titik kebocoran biaya terbesar di luar turnaround itu sendiri. Electrorefinery justru paling efisien, hemat 1,1% dari budget.

### Cost per ton cathode tetap stabil meski kondisi makin menantang

$471,8/t (2025) → $465,6/t (2026) — turun 1,3%, meski kadar Cu feed menurun dan volume produksi lebih rendah. Ini sinyal positif: disiplin biaya operasional per unit output tetap terjaga walau kondisi bijih makin menantang.

### Listrik bukan area prioritas

Variance listrik didominasi efek volume: hemat $1,6 juta dari sisi pemakaian MWh (karena produksi lebih rendah akibat downtime), rugi tipis $85 ribu dari sisi tarif. Penghematan ini kebetulan efek samping dari downtime, bukan efisiensi energi yang disengaja.

### Transparansi data

Masih ada 8 baris data cost dengan status "Missing Actual" di periode Closed — perlu disebutkan ke stakeholder sebelum klaim angka cost final 100% akurat.

## 3. Operasional & PPC

### Availability di bawah target

Rata-rata 91,91%, sedikit di bawah target 92,5%. 106 dari 608 hari (17%) availability-nya di bawah 90% — ini akar penyebab utama yang membuat angka plan vs actual feed bulanan sering meleset, dan menjembatani langsung ke temuan downtime di atas.

### Kadar Cu feed menurun

Turun dari 25,91% (2025) ke 24,84% (2026) — penurunan 1,07 poin persentase. Ini bukan sesuatu yang bisa diperbaiki lewat maintenance, tapi perlu dikomunikasikan ke tim PPC supaya target produksi 2027 disusun realistis, bukan berbasis asumsi grade lama.

## Rekomendasi

1. **Prioritaskan maintenance 2027 ke 5 equipment kritis** — Flash Smelting Furnace, Acid Plant, Concentrate Dryer, Oxygen Plant, Anode Furnace. Kelimanya menyumbang 77,3% dari total downtime tak terencana; ROI investasi maintenance di sini jauh lebih tinggi dibanding disebar rata ke 14 equipment.

2. **Evaluasi skema kontrak jasa turnaround** — pertimbangkan beralih dari time-and-material ke fixed-price, atau perketat scope control. Contractors & Services adalah penyebab tunggal terbesar overrun biaya ($1,56 juta, +36,4%).

3. **Siapkan SOP darurat dan stok spare part kritis untuk Acid Plant** — equipment ini jarang gagal, tapi saat gagal butuh waktu perbaikan paling lama dari seluruh plant (17,7 jam). Investasi kesiapan respons lebih relevan di sini dibanding investasi preventive maintenance.

4. **Revisi target produksi 2027 mengikuti tren penurunan grade** — jangan gunakan asumsi kadar Cu 2025 untuk perencanaan 2027; gap 1,07 poin ini berdampak langsung ke proyeksi cathode dan acid.

5. **Pertahankan disiplin cost per ton yang sudah baik** — cost per ton cathode stabil meski kondisi makin menantang; dokumentasikan praktik yang sudah berjalan baik di Electrorefinery (cost center paling efisien) sebagai benchmark internal untuk cost center lain.

> Seluruh data dan angka pada dokumen ini bersumber dari dataset sintetis yang dibuat untuk keperluan portofolio data analyst, bukan data operasional PT Amman Mineral Nusa Tenggara atau perusahaan tambang mana pun yang sesungguhnya.
