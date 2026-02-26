#!/usr/bin/env python3
"""
DEMO: Simulação do pipeline com dados realistas
baseados na estrutura real do Portal BASE.

Corre isto para ver o tipo de output que a análise produz.
"""

import pandas as pd
import numpy as np
import json
from pathlib import Path

np.random.seed(42)

# ============================================================
# GERAR DADOS SIMULADOS (estrutura real do Portal BASE)
# ============================================================

# As colunas do Portal BASE (confirmadas pela documentação)
# idcontrato, nifAdjudicante, nifAdjudicatario, nomeAdjudicante,
# nomeAdjudicatario, objectoContrato, tipoProcedimento,
# precoContratual, dataCelebracaoContrato, dataDR, cpv, etc.

ENTIDADES_ADJUDICANTES = [
    ("500100144", "Câmara Municipal de Lisboa"),
    ("500100152", "Câmara Municipal do Porto"),
    ("500100179", "Câmara Municipal de Braga"),
    ("500100187", "Câmara Municipal de Coimbra"),
    ("500100195", "Câmara Municipal de Setúbal"),
    ("500100209", "Câmara Municipal de Gondomar"),
    ("500100217", "Câmara Municipal de Oeiras"),
    ("500100225", "Câmara Municipal de Cascais"),
    ("500100233", "Câmara Municipal de Sintra"),
    ("500100241", "Câmara Municipal de Leiria"),
    ("500100250", "Câmara Municipal de Viseu"),
    ("600100100", "INEM, I.P."),
    ("600100200", "SPMS — Serviços Partilhados Min. Saúde"),
    ("600100300", "Instituto da Segurança Social, I.P."),
    ("600100400", "Metro do Porto, S.A."),
]

FORNECEDORES_NORMAIS = [
    ("509000101", "TecnoServ - Soluções Informáticas, Lda."),
    ("509000102", "Construções Ribeiro & Filhos, S.A."),
    ("509000103", "Limpurbe - Serviços Urbanos, Lda."),
    ("509000104", "GreenPark - Jardins e Espaços Verdes, Lda."),
    ("509000105", "AutoFrota - Gestão de Veículos, S.A."),
    ("509000106", "SecurPT - Segurança e Vigilância, Lda."),
    ("509000107", "AlimentaPlus - Catering, S.A."),
    ("509000108", "Digital360 - Consultoria TI, Lda."),
    ("509000109", "EngePlus - Engenharia Civil, S.A."),
    ("509000110", "MediSupply - Material Hospitalar, Lda."),
    ("509000111", "FormaPro - Formação Profissional, Lda."),
    ("509000112", "TransPortuga - Transportes, S.A."),
    ("509000113", "ArquiDesign - Arquitectura, Lda."),
    ("509000114", "AquaPura - Tratamento de Águas, S.A."),
    ("509000115", "PaviStrada - Pavimentações, Lda."),
]

# Empresas "suspeitas" — padrões anómalos intencionais
FORNECEDORES_SUSPEITOS = [
    ("509999001", "ABC Construções, Lda."),          # Fragmentação
    ("509999002", "XYZ MediaPro Comunicação, Lda."),  # Fragmentação
    ("509999003", "Nova Obra, Unip., Lda."),          # Mesma morada
    ("509999004", "ConstroiMais, Unip., Lda."),       # Mesma morada
    ("509999005", "EngeStar, Unip., Lda."),            # Mesma morada
    ("509999006", "Tecniredes, S.A."),                 # Fornecedor dominante
]

TIPOS_PROCEDIMENTO = [
    "Ajuste Direto",
    "Ajuste Direto Simplificado",
    "Concurso Público",
    "Concurso Limitado por Prévia Qualificação",
    "Procedimento de Negociação",
    "Consulta Prévia",
]

OBJETOS = [
    "Prestação de serviços de manutenção",
    "Empreitada de obras públicas",
    "Aquisição de equipamento informático",
    "Serviços de consultoria",
    "Fornecimento de material de escritório",
    "Serviços de limpeza e higiene",
    "Obras de requalificação urbana",
    "Serviços de segurança e vigilância",
    "Fornecimento de refeições",
    "Serviços de comunicação e marketing",
    "Manutenção de espaços verdes",
    "Reparação de vias municipais",
    "Serviços de formação profissional",
    "Aquisição de viaturas",
    "Serviços de transporte escolar",
]

def gerar_contratos(n=5000):
    """Gera contratos simulados com padrões anómalos embutidos."""
    
    contratos = []
    
    # --- Contratos normais (70%) ---
    for _ in range(int(n * 0.7)):
        adj_nipc, adj_nome = ENTIDADES_ADJUDICANTES[np.random.randint(len(ENTIDADES_ADJUDICANTES))]
        forn_nipc, forn_nome = FORNECEDORES_NORMAIS[np.random.randint(len(FORNECEDORES_NORMAIS))]
        tipo = np.random.choice(TIPOS_PROCEDIMENTO, p=[0.3, 0.15, 0.3, 0.05, 0.1, 0.1])
        
        if "Concurso" in tipo:
            preco = np.random.lognormal(11, 1.5)  # Valores maiores
        else:
            preco = np.random.lognormal(8, 1.2)
        
        mes = np.random.choice(range(1, 13), p=[
            0.07, 0.08, 0.09, 0.08, 0.08, 0.08, 
            0.08, 0.06, 0.09, 0.09, 0.10, 0.10
        ])
        dia = np.random.randint(1, 29)
        ano = np.random.choice([2024, 2025], p=[0.4, 0.6])
        
        contratos.append({
            "nifAdjudicante": adj_nipc,
            "nomeAdjudicante": adj_nome,
            "nifAdjudicatario": forn_nipc,
            "nomeAdjudicatario": forn_nome,
            "objectoContrato": np.random.choice(OBJETOS),
            "tipoProcedimento": tipo,
            "precoContratual": round(preco, 2),
            "dataCelebracaoContrato": f"{ano}-{mes:02d}-{dia:02d}",
        })
    
    # --- ANOMALIA 1: Fragmentação (ABC Construções → CM Gondomar) ---
    # 52 ajustes diretos logo abaixo de €20K
    for i in range(52):
        mes = np.random.choice(range(1, 13))
        dia = np.random.randint(1, 29)
        contratos.append({
            "nifAdjudicante": "500100209",
            "nomeAdjudicante": "Câmara Municipal de Gondomar",
            "nifAdjudicatario": "509999001",
            "nomeAdjudicatario": "ABC Construções, Lda.",
            "objectoContrato": np.random.choice([
                "Reparação de passeios - Zona Norte",
                "Manutenção de drenagem pluvial",
                "Reparação de pavimento - Rua X",
                "Obras de conservação - Escola EB1",
                "Manutenção de edifício municipal",
            ]),
            "tipoProcedimento": "Ajuste Direto Simplificado",
            "precoContratual": round(np.random.uniform(15000, 19900), 2),
            "dataCelebracaoContrato": f"2025-{mes:02d}-{dia:02d}",
        })
    
    # --- ANOMALIA 2: Fragmentação (XYZ MediaPro → CM Oeiras) ---
    for i in range(47):
        mes = np.random.choice(range(1, 13))
        dia = np.random.randint(1, 29)
        contratos.append({
            "nifAdjudicante": "500100217",
            "nomeAdjudicante": "Câmara Municipal de Oeiras",
            "nifAdjudicatario": "509999002",
            "nomeAdjudicatario": "XYZ MediaPro Comunicação, Lda.",
            "objectoContrato": np.random.choice([
                "Produção de conteúdos multimédia",
                "Gestão de redes sociais - Mês X",
                "Design gráfico - Agenda Cultural",
                "Produção de vídeo institucional",
                "Serviços de fotografia - Evento",
            ]),
            "tipoProcedimento": "Ajuste Direto",
            "precoContratual": round(np.random.uniform(12000, 19500), 2),
            "dataCelebracaoContrato": f"2025-{mes:02d}-{dia:02d}",
        })
    
    # --- ANOMALIA 3: Concentração temporal (CM Cascais, tudo em Nov/Dez) ---
    for i in range(120):
        mes = np.random.choice([11, 12], p=[0.4, 0.6])
        dia = np.random.randint(1, 29)
        forn_nipc, forn_nome = FORNECEDORES_NORMAIS[np.random.randint(len(FORNECEDORES_NORMAIS))]
        contratos.append({
            "nifAdjudicante": "500100225",
            "nomeAdjudicante": "Câmara Municipal de Cascais",
            "nifAdjudicatario": forn_nipc,
            "nomeAdjudicatario": forn_nome,
            "objectoContrato": np.random.choice(OBJETOS),
            "tipoProcedimento": "Ajuste Direto",
            "precoContratual": round(np.random.lognormal(9, 1), 2),
            "dataCelebracaoContrato": f"2025-{mes:02d}-{dia:02d}",
        })
    
    # --- ANOMALIA 4: Fornecedor dominante (Tecniredes → CM Leiria, 45% do valor) ---
    for i in range(25):
        mes = np.random.choice(range(1, 13))
        dia = np.random.randint(1, 29)
        contratos.append({
            "nifAdjudicante": "500100241",
            "nomeAdjudicante": "Câmara Municipal de Leiria",
            "nifAdjudicatario": "509999006",
            "nomeAdjudicatario": "Tecniredes, S.A.",
            "objectoContrato": "Empreitada de obras públicas - Lote " + str(i+1),
            "tipoProcedimento": np.random.choice(["Concurso Público", "Ajuste Direto"]),
            "precoContratual": round(np.random.uniform(80000, 350000), 2),
            "dataCelebracaoContrato": f"2025-{mes:02d}-{dia:02d}",
        })
    
    # Contratos normais para CM Leiria (para que Tecniredes se destaque)
    for i in range(35):
        mes = np.random.choice(range(1, 13))
        dia = np.random.randint(1, 29)
        forn_nipc, forn_nome = FORNECEDORES_NORMAIS[np.random.randint(len(FORNECEDORES_NORMAIS))]
        contratos.append({
            "nifAdjudicante": "500100241",
            "nomeAdjudicante": "Câmara Municipal de Leiria",
            "nifAdjudicatario": forn_nipc,
            "nomeAdjudicatario": forn_nome,
            "objectoContrato": np.random.choice(OBJETOS),
            "tipoProcedimento": np.random.choice(TIPOS_PROCEDIMENTO[:4]),
            "precoContratual": round(np.random.lognormal(9, 1.2), 2),
            "dataCelebracaoContrato": f"2025-{mes:02d}-{dia:02d}",
        })
    
    return pd.DataFrame(contratos)


def gerar_entidades():
    """Gera entidades com anomalia de mesma morada."""
    entidades = []
    
    # Entidades normais
    moradas = [
        "Rua Augusta, 100, 1100-053 Lisboa",
        "Av. dos Aliados, 45, 4000-066 Porto",
        "Praça da República, 10, 4710-305 Braga",
        "Rua Ferreira Borges, 77, 3000-180 Coimbra",
        "Largo do Município, 1, 2900-098 Setúbal",
        "Praça Manuel Guedes, 1, 4434-501 Gondomar",
        "Largo Marquês de Pombal, 1, 2784-501 Oeiras",
        "Largo da Misericórdia, 1, 2754-501 Cascais",
    ]
    
    all_fornecedores = FORNECEDORES_NORMAIS + FORNECEDORES_SUSPEITOS
    for i, (nipc, nome) in enumerate(all_fornecedores):
        entidades.append({
            "nif": nipc,
            "designacao": nome,
            "morada": moradas[i % len(moradas)] if nipc not in ["509999003", "509999004", "509999005"] else "Rua Oculta, 13, 2ºD, 1500-001 Lisboa",
        })
    
    for nipc, nome in ENTIDADES_ADJUDICANTES:
        entidades.append({
            "nif": nipc,
            "designacao": nome,
            "morada": moradas[hash(nipc) % len(moradas)],
        })
    
    return pd.DataFrame(entidades)


# ============================================================
# ANÁLISES (mesmas do script principal)
# ============================================================

def analise_fragmentacao(df, limiar=20000, min_contratos=10):
    print("\n🔍 ANÁLISE 1: Fragmentação de contratos")
    print("   Múltiplos ajustes diretos à mesma empresa abaixo de €20K")
    print("-" * 60)
    
    mask_tipo = df["tipoProcedimento"].str.contains("Direto|Directo|Simplificado", case=False, na=False)
    mask_preco = df["precoContratual"] < limiar
    sub = df[mask_tipo & mask_preco].copy()
    
    agg = sub.groupby(["nomeAdjudicante", "nomeAdjudicatario", "nifAdjudicatario"]).agg(
        n_contratos=("precoContratual", "count"),
        total=("precoContratual", "sum"),
        media=("precoContratual", "mean"),
        min_val=("precoContratual", "min"),
        max_val=("precoContratual", "max"),
    ).reset_index()
    
    suspeitos = agg[agg["n_contratos"] >= min_contratos].sort_values("total", ascending=False)
    
    print(f"\n  ⚠️  {len(suspeitos)} PARES SUSPEITOS (≥{min_contratos} ajustes diretos <€{limiar:,})\n")
    
    for _, row in suspeitos.iterrows():
        print(f"  ┌─ ALERTA ─────────────────────────────────────────────")
        print(f"  │ Adjudicatário: {row['nomeAdjudicatario']}")
        print(f"  │ NIPC:          {row['nifAdjudicatario']}")
        print(f"  │ Adjudicante:   {row['nomeAdjudicante']}")
        print(f"  │ Contratos:     {row['n_contratos']}")
        print(f"  │ Valor total:   €{row['total']:,.2f}")
        print(f"  │ Média:         €{row['media']:,.2f}")
        print(f"  │ Range:         €{row['min_val']:,.2f} — €{row['max_val']:,.2f}")
        if row['max_val'] < limiar and row['min_val'] > limiar * 0.6:
            print(f"  │ 🚩 PADRÃO: Valores consistentemente próximos do limiar")
        print(f"  └──────────────────────────────────────────────────────\n")
    
    return suspeitos


def analise_concentracao_temporal(df):
    print("\n🔍 ANÁLISE 2: Concentração temporal de contratos")
    print("   Concentração anómala em meses específicos por entidade")
    print("-" * 60)
    
    df = df.copy()
    df["_data"] = pd.to_datetime(df["dataCelebracaoContrato"], errors="coerce")
    df["_mes"] = df["_data"].dt.month
    
    meses_pt = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun",
                "Jul", "Ago", "Set", "Out", "Nov", "Dez"]
    
    # Global
    por_mes = df.dropna(subset=["_mes"]).groupby("_mes").size()
    media = por_mes.mean()
    
    print(f"\n  Distribuição global ({len(df):,} contratos):\n")
    for m in range(1, 13):
        n = por_mes.get(m, 0)
        pct = n / media * 100
        bar = "█" * int(pct / 8)
        flag = " ⚠️  PICO" if pct > 150 else ""
        print(f"    {meses_pt[m-1]}: {n:>5}  ({pct:>5.0f}%) {bar}{flag}")
    
    # Por entidade — detetar quem concentra
    print(f"\n  Entidades com concentração anómala (>40% num só mês):\n")
    for ent in df["nomeAdjudicante"].unique():
        sub = df[df["nomeAdjudicante"] == ent].dropna(subset=["_mes"])
        if len(sub) < 20:
            continue
        por_mes_ent = sub.groupby("_mes").size()
        max_mes = por_mes_ent.idxmax()
        max_pct = por_mes_ent.max() / por_mes_ent.sum() * 100
        if max_pct > 25:
            print(f"  ┌─ {ent}")
            print(f"  │ {por_mes_ent.max()} de {por_mes_ent.sum()} contratos ({max_pct:.0f}%) em {meses_pt[int(max_mes)-1]}")
            print(f"  └──────────────────────────────────────────────────────")


def analise_fornecedor_dominante(df):
    print("\n🔍 ANÁLISE 3: Fornecedores dominantes por entidade")
    print("   Fornecedor com >30% do valor total de uma entidade")
    print("-" * 60)
    
    total_adj = df.groupby("nomeAdjudicante")["precoContratual"].sum().reset_index(name="total_ent")
    par = df.groupby(["nomeAdjudicante", "nomeAdjudicatario", "nifAdjudicatario"]).agg(
        n=("precoContratual", "count"),
        total=("precoContratual", "sum"),
    ).reset_index()
    
    merged = par.merge(total_adj, on="nomeAdjudicante")
    merged["quota"] = (merged["total"] / merged["total_ent"] * 100).round(1)
    
    suspeitos = merged[merged["quota"] >= 25].sort_values("quota", ascending=False)
    
    print(f"\n  ⚠️  {len(suspeitos)} PARES com fornecedor dominante (≥25% do valor)\n")
    
    for _, row in suspeitos.head(10).iterrows():
        print(f"  ┌─ ALERTA ─────────────────────────────────────────────")
        print(f"  │ Fornecedor:  {row['nomeAdjudicatario']}")
        print(f"  │ NIPC:        {row['nifAdjudicatario']}")
        print(f"  │ Entidade:    {row['nomeAdjudicante']}")
        print(f"  │ Quota:       {row['quota']}% do valor total da entidade")
        print(f"  │ Valor:       €{row['total']:,.2f} de €{row['total_ent']:,.2f}")
        print(f"  │ Contratos:   {row['n']}")
        print(f"  └──────────────────────────────────────────────────────\n")


def analise_mesma_morada(df_ent):
    print("\n🔍 ANÁLISE 4: Empresas com mesma morada fiscal")
    print("   Possível indicador de empresas de fachada")
    print("-" * 60)
    
    dup = df_ent.groupby("morada").agg(
        n=("nif", "count"),
        empresas=("designacao", list),
        nipcs=("nif", list),
    ).reset_index()
    dup = dup[dup["n"] >= 3].sort_values("n", ascending=False)
    
    print(f"\n  ⚠️  {len(dup)} MORADAS partilhadas por ≥3 entidades\n")
    for _, row in dup.iterrows():
        print(f"  ┌─ {row['morada']}")
        print(f"  │ {row['n']} entidades:")
        for nome, nipc in zip(row["empresas"], row["nipcs"]):
            print(f"  │   • {nome} (NIPC: {nipc})")
        print(f"  └──────────────────────────────────────────────────────\n")


# ============================================================
# MAIN
# ============================================================

def main():
    print("""
╔══════════════════════════════════════════════════════════════════╗
║  OBSERVATÓRIO DE INTEGRIDADE — DEMONSTRAÇÃO                     ║
║                                                                  ║
║  Dados simulados baseados na estrutura real do Portal BASE       ║
║  Colunas: nifAdjudicante, nifAdjudicatario, precoContratual,    ║
║           tipoProcedimento, dataCelebracaoContrato, etc.         ║
╚══════════════════════════════════════════════════════════════════╝
    """)
    
    print("Gerar dados simulados...")
    df = gerar_contratos(5000)
    df_ent = gerar_entidades()
    
    print(f"\n📦 Dataset gerado:")
    print(f"   Contratos: {len(df):,}")
    print(f"   Entidades: {len(df_ent):,}")
    print(f"   Valor total: €{df['precoContratual'].sum():,.2f}")
    print(f"   Período: {df['dataCelebracaoContrato'].min()} a {df['dataCelebracaoContrato'].max()}")
    print(f"   Tipos de procedimento: {df['tipoProcedimento'].value_counts().to_dict()}")
    
    analise_fragmentacao(df)
    analise_concentracao_temporal(df)
    analise_fornecedor_dominante(df)
    analise_mesma_morada(df_ent)
    
    print("""
╔══════════════════════════════════════════════════════════════════╗
║  RESUMO DE ALERTAS                                               ║
║                                                                  ║
║  Este demo mostra 4 tipos de deteção automática:                 ║
║                                                                  ║
║  1. FRAGMENTAÇÃO — Ajustes diretos repetidos <€20K               ║
║     → Indício de divisão artificial para evitar concurso         ║
║                                                                  ║
║  2. CONCENTRAÇÃO TEMPORAL — Picos em Nov/Dez                     ║
║     → Gasto apressado de orçamento no fim do ano                 ║
║                                                                  ║
║  3. FORNECEDOR DOMINANTE — >25% do valor de uma entidade         ║
║     → Possível relação preferencial ou captura                   ║
║                                                                  ║
║  4. MESMA MORADA — Múltiplas empresas no mesmo endereço          ║
║     → Possíveis empresas de fachada ou conluio                   ║
║                                                                  ║
║  Tudo isto usa APENAS dados públicos do Portal BASE.             ║
║  Sem NIFs pessoais. Sem dados privados. 100% legal.              ║
╚══════════════════════════════════════════════════════════════════╝
    """)

    # Exportar
    Path("output").mkdir(exist_ok=True)
    df.to_csv("output/contratos_demo.csv", index=False, encoding="utf-8-sig")
    df_ent.to_csv("output/entidades_demo.csv", index=False, encoding="utf-8-sig")
    print("  Ficheiros exportados para output/")


if __name__ == "__main__":
    main()
