#!/usr/bin/env python3
"""
Observatório de Integridade — Extração Portal BASE v3
========================================================

Usa o Portal da Transparência do SNS (transparencia.sns.gov.pt)
que disponibiliza os MESMOS dados do Portal BASE numa interface
de dados abertos que funciona sem ficheiros com carimbos temporais.

Fonte alternativa: dados.gov.pt (descarregamento manual)

Uso:
  pip install pandas requests
  python extrair_base.py
"""

import sys
import json
from pathlib import Path
from datetime import datetime

try:
    import pandas as pd
    import requests
except ImportError:
    print("Instala: pip install pandas requests")
    sys.exit(1)

DIR = Path("dados_base")
DIR.mkdir(exist_ok=True)

# ════════════════════════════════════════
# FONTES DE DADOS
# ════════════════════════════════════════

# API OpenDataSoft do Portal da Transparência SNS
# Conjunto: portal-base (contratos públicos — mesmos dados do BASE)
# Documentação: https://transparencia.sns.gov.pt/explore/dataset/portal-base/api/
SNS_BASE = "https://transparencia.sns.gov.pt"
SNS_DATASET = "portal-base"

# Exportação directa em CSV (até 10.000 registos por pedido)
SNS_EXPORT = f"{SNS_BASE}/api/explore/v2.1/catalog/datasets/{SNS_DATASET}/exports/csv"

# Consulta de registos (paginada, sem limite)
SNS_RECORDS = f"{SNS_BASE}/api/explore/v2.1/catalog/datasets/{SNS_DATASET}/records"

# Ligação directa para descarregamento completo (sem limite de registos)
SNS_COMPLETO = f"{SNS_BASE}/explore/dataset/{SNS_DATASET}/download/?format=csv&timezone=Europe/Lisbon"


# ════════════════════════════════════════
# 1. DESCARREGAMENTO
# ════════════════════════════════════════

def contar_registos():
    """Consulta quantos registos existem no conjunto de dados."""
    try:
        r = requests.get(SNS_RECORDS, params={"limit": 0}, timeout=30)
        r.raise_for_status()
        total = r.json().get("total_count", 0)
        return total
    except Exception as e:
        print(f"  ⚠ Erro ao consultar API: {e}")
        return 0


def descarregar_via_export(path, limit=10000):
    """Descarrega via interface de exportação (rápido, até 10 mil registos)."""
    print(f"  ↓ A descarregar via exportação (limite: {limit})...")
    params = {
        "delimiter": ";",
        "list_separator": "|",
        "limit": limit,
        "offset": 0,
    }
    try:
        r = requests.get(SNS_EXPORT, params=params, timeout=120)
        r.raise_for_status()
        with open(path, "wb") as f:
            f.write(r.content)
        print(f"  ✓ {path.name} ({path.stat().st_size / 1e6:.1f} MB)")
        return True
    except Exception as e:
        print(f"  ✗ {e}")
        return False


def descarregar_completo(path):
    """Descarrega o CSV completo via ligação directa."""
    print(f"  ↓ A descarregar CSV completo...")
    try:
        r = requests.get(SNS_COMPLETO, timeout=300, stream=True)
        r.raise_for_status()
        total = int(r.headers.get("content-length", 0))
        recebido = 0
        with open(path, "wb") as f:
            for pedaço in r.iter_content(65536):
                f.write(pedaço)
                recebido += len(pedaço)
                if total:
                    print(f"\r    {recebido/1e6:.1f}/{total/1e6:.1f} MB", end="", flush=True)
        print()
        if path.stat().st_size > 100:
            print(f"  ✓ {path.name} ({path.stat().st_size / 1e6:.1f} MB)")
            return True
    except Exception as e:
        print(f"  ✗ {e}")
    return False


def descarregar_paginado(path, lote=100):
    """Descarrega por páginas (mais lento, mas fiável)."""
    print(f"  ↓ A descarregar por páginas (lotes de {lote})...")
    registos = []
    offset = 0
    total = contar_registos()
    if total == 0:
        print("  ✗ Sem registos")
        return False
    
    print(f"    Total: {total:,} registos")
    
    while offset < total:
        try:
            r = requests.get(SNS_RECORDS, params={
                "limit": lote,
                "offset": offset,
            }, timeout=60)
            r.raise_for_status()
            dados = r.json()
            resultados = dados.get("results", [])
            if not resultados:
                break
            for reg in resultados:
                registos.append(reg.get("record", {}).get("fields", reg))
            offset += lote
            print(f"\r    {len(registos):,} / {total:,}", end="", flush=True)
        except Exception as e:
            print(f"\n  ⚠ Erro na posição {offset}: {e}")
            break
    
    print()
    if registos:
        df = pd.DataFrame(registos)
        df.to_csv(path, index=False, encoding="utf-8-sig", sep=";")
        print(f"  ✓ {path.name} ({len(registos):,} registos)")
        return True
    return False


def obter_dados():
    """Tenta várias formas de obter os dados."""
    print("\n═══ FASE 1: DESCARREGAMENTO ═══\n")
    
    # Verificar ficheiro local
    for f in DIR.glob("*.csv"):
        if f.stat().st_size > 1000:
            print(f"  ✓ Ficheiro local encontrado: {f.name} ({f.stat().st_size/1e6:.1f} MB)")
            return f
    for f in DIR.glob("*.xlsx"):
        if f.stat().st_size > 1000:
            print(f"  ✓ Ficheiro local encontrado: {f.name} ({f.stat().st_size/1e6:.1f} MB)")
            return f
    
    path = DIR / "portal_base.csv"
    
    # Contar registos
    total = contar_registos()
    if total > 0:
        print(f"  📊 {total:,} registos disponíveis na API")
    
    # Tentativa 1: Descarregamento completo
    if descarregar_completo(path):
        return path
    
    # Tentativa 2: Exportação por lotes
    if descarregar_via_export(path, limit=min(total, 10000)):
        return path
    
    # Tentativa 3: Consulta por páginas
    if total > 0:
        if descarregar_paginado(path):
            return path
    
    print("\n  ✗ Não foi possível descarregar os dados.")
    print("  Alternativas:")
    print(f"  1. Abre: {SNS_BASE}/explore/dataset/{SNS_DATASET}/export/?sort=datacelebracaocontrato")
    print(f"     Descarrega o CSV e coloca na pasta {DIR}/")
    print(f"  2. Abre: https://dados.gov.pt/en/datasets/contratos-publicos-portal-base-impic-contratos-de-2012-a-2026/")
    print(f"     Descarrega qualquer ficheiro xlsx e coloca na pasta {DIR}/")
    return None


# ════════════════════════════════════════
# 2. CARREGAMENTO
# ════════════════════════════════════════

def carregar(path):
    """Carrega CSV ou XLSX."""
    print(f"\n  📄 A ler {path.name}...")
    
    if path.suffix == ".xlsx":
        try:
            import openpyxl
        except ImportError:
            print("  Instala: pip install openpyxl")
            sys.exit(1)
        df = pd.read_excel(path, engine="openpyxl")
    elif path.suffix == ".csv":
        for sep in [";", ",", "\t"]:
            for enc in ["utf-8-sig", "utf-8", "latin-1", "cp1252"]:
                try:
                    df = pd.read_csv(path, sep=sep, encoding=enc, low_memory=False)
                    if len(df.columns) > 3:
                        break
                except:
                    continue
            else:
                continue
            break
        else:
            print("  ✗ Não consegui ler o CSV"); return None
    else:
        print(f"  ✗ Formato não suportado: {path.suffix}"); return None
    
    print(f"  → {len(df):,} registos, {len(df.columns)} colunas")
    print(f"  → Colunas: {list(df.columns)}")
    return df


def normalizar(df):
    """Normaliza nomes de colunas — suporta tanto dados.gov.pt como transparencia.sns.gov.pt."""
    
    # Mapeamento: nome interno → lista de variantes possíveis nas fontes
    correspondencias = {
        "nipc_adjudicatario": [
            "nifs_das_adjudicatarias",          # transparencia.sns.gov.pt
            "nifadjudicatario",                  # dados.gov.pt
            "adjudicatarionif", "adjudicatario_nif",
        ],
        "nome_adjudicatario": [
            "entidades_adjudicatarias_normalizado",  # transparencia.sns.gov.pt
            "nomeadjudicatario",                      # dados.gov.pt
            "adjudicatariodesignacao", "adjudicatario_designacao",
        ],
        "nipc_adjudicante": [
            "nifs_dos_adjudicantes",             # transparencia.sns.gov.pt
            "nifadjudicante",                    # dados.gov.pt
            "adjudicantenif", "adjudicante_nif",
        ],
        "nome_adjudicante": [
            "entidades_adjudicantes_normalizado",  # transparencia.sns.gov.pt
            "nomeadjudicante",                      # dados.gov.pt
            "adjudicantedesignacao", "adjudicante_designacao",
        ],
        "preco": [
            "preco_contratual",                  # transparencia.sns.gov.pt
            "precocontratual",                   # dados.gov.pt
            "precoefetivo",
        ],
        "tipo_procedimento": [
            "tipo_de_procedimento",              # transparencia.sns.gov.pt
            "tipoprocedimento",                  # dados.gov.pt
            "tipodeprocedimento",
        ],
        "data_celebracao": [
            "data_de_celebracao_do_contrato",    # transparencia.sns.gov.pt
            "datacelebracaocontrato",            # dados.gov.pt
            "datacelebracao", "data_celebracao",
        ],
        "objeto": [
            "objeto_do_contrato",                # transparencia.sns.gov.pt
            "objectocontrato",                   # dados.gov.pt
            "objetocontrato",
        ],
        "tipo_contrato": [
            "tipos_de_contrato",                 # transparencia.sns.gov.pt
            "tipocontrato",                      # dados.gov.pt
        ],
        "local_execucao": [
            "local_de_execucao",                 # transparencia.sns.gov.pt
        ],
        "preco_efetivo": [
            "preco_total_efetivo",               # transparencia.sns.gov.pt
        ],
    }
    
    # Criar índice das colunas reais (sem espaços, sublinhados, hífenes)
    indice = {}
    for c in df.columns:
        chave = c.lower().strip().replace(" ","").replace("-","")
        indice[chave] = c
        # Também sem sublinhados para apanhar variantes
        chave2 = chave.replace("_","")
        indice[chave2] = c
    
    renomear = {}
    for alvo, candidatos in correspondencias.items():
        for cand in candidatos:
            # Tentar com sublinhados
            if cand in [c.lower() for c in df.columns]:
                col_real = [c for c in df.columns if c.lower() == cand][0]
                renomear[col_real] = alvo
                break
            # Tentar sem sublinhados
            limpo = cand.lower().replace("_","")
            if limpo in indice:
                renomear[indice[limpo]] = alvo
                break
    
    if renomear:
        df = df.rename(columns=renomear)
        print(f"  → Colunas normalizadas: {list(renomear.values())}")
    
    return df


# ════════════════════════════════════════
# 3. ANÁLISES
# ════════════════════════════════════════

def analise_fragmentacao(df, limiar=20000, minimo=5):
    """Detecta fragmentação: ajustes directos repetidos abaixo do limiar legal."""
    print("\n🔍 FRAGMENTAÇÃO DE CONTRATOS")
    print(f"   Ajustes directos repetidos abaixo de €{limiar:,}")
    print("─" * 55)
    
    if "preco" not in df.columns:
        print("  ⚠ Sem coluna de preço"); return
    
    t = df.copy()
    t["_p"] = pd.to_numeric(t["preco"], errors="coerce")
    
    if "tipo_procedimento" in t.columns:
        t = t[t["tipo_procedimento"].str.contains("direto|directo|simplif", case=False, na=False)]
    
    t = t[t["_p"] < limiar]
    
    colunas = [c for c in ["nome_adjudicante","nome_adjudicatario","nipc_adjudicatario"] if c in t.columns]
    if not colunas:
        print("  ⚠ Sem colunas de agrupamento"); return
    
    a = t.groupby(colunas).agg(
        n=("_p","count"), total=("_p","sum"), media=("_p","mean"),
        mn=("_p","min"), mx=("_p","max")
    ).reset_index()
    
    s = a[a["n"] >= minimo].sort_values("total", ascending=False)
    
    print(f"\n  ⚠ {len(s)} pares suspeitos (≥{minimo} ajustes directos <€{limiar:,})\n")
    for _, r in s.head(15).iterrows():
        print(f"  ┌ {r.get('nome_adjudicatario','?')}")
        nipc = r.get('nipc_adjudicatario','')
        if nipc:
            print(f"  │ NIPC: {nipc}")
        print(f"  │ ← {r.get('nome_adjudicante','?')}")
        print(f"  │ {r['n']} contratos  €{r['total']:,.0f} (média €{r['media']:,.0f})")
        if r["mx"] < limiar and r["mn"] > limiar * 0.6:
            print(f"  │ 🚩 Valores sistematicamente junto ao limiar!")
        print(f"  └{'─'*53}\n")


def analise_temporal(df):
    """Detecta concentração temporal anómala."""
    print("\n🔍 CONCENTRAÇÃO TEMPORAL")
    print("─" * 55)
    
    if "data_celebracao" not in df.columns:
        print("  ⚠ Sem coluna de data"); return
    
    t = df.copy()
    t["_d"] = pd.to_datetime(t["data_celebracao"], errors="coerce")
    t["_m"] = t["_d"].dt.month
    
    meses = ["Jan","Fev","Mar","Abr","Mai","Jun","Jul","Ago","Set","Out","Nov","Dez"]
    pm = t.dropna(subset=["_m"]).groupby("_m").size()
    media = pm.mean()
    
    print(f"\n  Média: {media:.0f} contratos/mês\n")
    for m in range(1,13):
        n = pm.get(m,0)
        p = n/media*100 if media else 0
        print(f"    {meses[m-1]}: {n:>6,}  ({p:>5.0f}%) {'█'*int(p/8)}{'  ⚠ PICO' if p>150 else ''}")


def analise_dominante(df, quota_min=25):
    """Detecta fornecedores dominantes numa entidade."""
    print(f"\n🔍 FORNECEDORES DOMINANTES (>{quota_min}%)")
    print("─" * 55)
    
    if "preco" not in df.columns: return
    t = df.copy()
    t["_p"] = pd.to_numeric(t["preco"], errors="coerce")
    
    ca = "nome_adjudicante"
    cf = "nome_adjudicatario"
    if ca not in t.columns or cf not in t.columns: return
    
    te = t.groupby(ca)["_p"].sum().reset_index(name="te")
    pa = t.groupby([ca,cf]).agg(n=("_p","count"), total=("_p","sum")).reset_index()
    m = pa.merge(te, on=ca)
    m["quota"] = (m["total"]/m["te"]*100).round(1)
    
    s = m[m["quota"] >= quota_min].sort_values("quota", ascending=False)
    print(f"\n  ⚠ {len(s)} pares com fornecedor dominante\n")
    for _,r in s.head(10).iterrows():
        print(f"  {r[cf][:50]}")
        print(f"    → {r[ca][:50]}  {r['quota']}%  €{r['total']:,.0f} ({r['n']} contratos)\n")


def analise_top(df, n=20):
    """Maiores adjudicatários por valor total."""
    print(f"\n🔍 MAIORES ADJUDICATÁRIOS (TOP {n})")
    print("─" * 55)
    
    if "preco" not in df.columns: return
    t = df.copy()
    t["_p"] = pd.to_numeric(t["preco"], errors="coerce")
    
    cf = "nome_adjudicatario"
    if cf not in t.columns: return
    
    a = t.groupby(cf).agg(n=("_p","count"), total=("_p","sum")).reset_index()
    a = a.sort_values("total", ascending=False)
    
    print()
    for i, (_, r) in enumerate(a.head(n).iterrows(), 1):
        print(f"  {i:>2}. {r[cf][:55]:<57} {r['n']:>5} contratos  €{r['total']:>14,.2f}")


def resumo(df):
    """Resumo do conjunto de dados."""
    print(f"\n📊 RESUMO")
    print("─" * 55)
    print(f"  Registos:  {len(df):,}")
    if "preco" in df.columns:
        v = pd.to_numeric(df["preco"], errors="coerce")
        print(f"  Valor total: €{v.sum():,.2f}")
        print(f"  Mediana:     €{v.median():,.2f}")
    if "tipo_procedimento" in df.columns:
        print(f"\n  Procedimentos:")
        for proc, n in df["tipo_procedimento"].value_counts().head(8).items():
            print(f"    {proc:<50} {n:>6,}")
    if "data_celebracao" in df.columns:
        d = pd.to_datetime(df["data_celebracao"], errors="coerce")
        print(f"\n  Período: {d.min()} — {d.max()}")


# ════════════════════════════════════════
# PRINCIPAL
# ════════════════════════════════════════

def main():
    print("""
╔══════════════════════════════════════════════════════╗
║  OBSERVATÓRIO DE INTEGRIDADE — PORTUGAL             ║
║  Extração Portal BASE v3                            ║
║                                                      ║
║  Fonte: transparencia.sns.gov.pt (Portal BASE)      ║
║  Licença: Dados abertos — Domínio Público           ║
╚══════════════════════════════════════════════════════╝
    """)
    
    caminho = obter_dados()
    
    if caminho is None:
        sys.exit(1)
    
    print("\n═══ FASE 2: CARREGAMENTO ═══")
    df = carregar(caminho)
    if df is None:
        sys.exit(1)
    
    df = normalizar(df)
    resumo(df)
    
    print("\n═══ FASE 3: ANÁLISE ═══")
    analise_fragmentacao(df)
    analise_temporal(df)
    analise_dominante(df)
    analise_top(df)
    
    # Exportar resultado limpo
    saida = DIR / "resultado.csv"
    df.to_csv(saida, index=False, encoding="utf-8-sig")
    print(f"\n  ✓ Exportado: {saida}")
    
    print(f"""
{'═'*55}
  Concluído. {len(df):,} contratos analisados.
  
  Próximos passos:
  · Cruzar NIPC com Registo Comercial (sócios/gerentes)
  · Cruzar nomes com listas de autarcas e deputados
  · Cruzar com doações a partidos (ECFP/CNE)
{'═'*55}
    """)


if __name__ == "__main__":
    main()