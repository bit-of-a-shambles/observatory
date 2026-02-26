import { useState, useEffect, useRef } from "react";
// import pre‑converted JSON version of the CSV
import contractsData from "./dados_base/resultado.json";




const INSIGHTS = [
  {
    id: 1,
    severity: "CRÍTICO",
    score: 97,
    title: "Auto-direcionamento de emendas",
    subtitle: "Câmara Municipal de Gondomar",
    amount: "€12.3M",
    description:
      "Autarca destinou €12.3M em contratos públicos para a Construções Ferreira & Filhos, Lda. (NIPC 509XXX123), empresa detida pelo cunhado. 73% dos contratos foram por ajuste direto, abaixo do limiar de €20k.",
    pattern: "AUTARCA → AJUSTES DIRETOS → EMPRESA FAMILIAR",
    sources: ["Portal BASE", "Registo Comercial", "DGAL", "Tribunal de Contas"],
    entities: { politico: "Vereador J.F.", empresa: "Construções Ferreira & Filhos, Lda.", relacao: "Cunhado" },
  },
  {
    id: 2,
    severity: "CRÍTICO",
    score: 94,
    title: "Funcionários fantasma",
    subtitle: "Junta de Freguesia de Benfica",
    amount: "~€890K/ano",
    description:
      "Cruzamento Segurança Social × servidores municipais: 21 pessoas simultaneamente empregadas na Limpezas Atlântico, Lda. e funcionários da Junta de Freguesia de Benfica.",
    pattern: "SEG. SOCIAL EMPRESA × FOLHA AUTARQUIA = DUPLO VÍNCULO",
    sources: ["Seg. Social", "Transparência Autárquica", "Registo Comercial"],
    entities: { politico: "Pres. Junta M.S.", empresa: "Limpezas Atlântico, Lda.", funcionarios: 21 },
  },
  {
    id: 3,
    severity: "CRÍTICO",
    score: 92,
    title: "IPSS fantasma a receber verbas",
    subtitle: "Distrito de Viseu",
    amount: "€340K",
    description:
      "IPSS 'Solidariedade do Dão' sem atividade registada desde 2019 continua a receber transferências da Câmara. Sede fiscal num terreno baldio. Presidente da direção é sobrinho do vereador.",
    pattern: "IPSS INATIVA → TRANSFERÊNCIAS CÂMARA → LIGAÇÃO FAMILIAR",
    sources: ["Portal BASE", "Seg. Social", "Registo Comercial", "Google Maps"],
    entities: { politico: "Vereador A.R.", ipss: "Solidariedade do Dão", relacao: "Sobrinho" },
  },
  {
    id: 4,
    severity: "CRÍTICO",
    score: 91,
    title: "Circuito fechado doação ↔ contratos",
    subtitle: "Câmara Municipal de Leiria",
    amount: "€5.2M + €45K",
    description:
      "Empresa Tecniredes, SA doou €45K ao partido do presidente da câmara em 2021. Desde então, recebeu €5.2M em contratos de obras públicas sem concurso público aberto.",
    pattern: "DOAÇÃO PARTIDO → ELEIÇÃO → CONTRATOS DIRETOS",
    sources: ["ECFP/CNE", "Portal BASE", "Compras Públicas", "TSE"],
    entities: { politico: "Pres. Câmara R.L.", empresa: "Tecniredes, SA", doacao: "€45K" },
  },
  {
    id: 5,
    severity: "ALTO",
    score: 85,
    title: "Fragmentação de contratos",
    subtitle: "Câmara Municipal de Oeiras",
    amount: "€2.8M",
    description:
      "47 contratos por ajuste direto à mesma empresa (MediaPro Comunicação) num período de 18 meses, todos abaixo de €20K. Valor agregado: €2.8M. Indícios de fragmentação para evitar concurso público.",
    pattern: "47× AJUSTE DIRETO < €20K → MESMA EMPRESA = €2.8M",
    sources: ["Portal BASE", "Compras Públicas"],
    entities: { empresa: "MediaPro Comunicação, Lda.", contratos: 47, media: "€59.6K" },
  },
  {
    id: 6,
    severity: "ALTO",
    score: 82,
    title: "Conflito de interesses não declarado",
    subtitle: "Assembleia da República",
    amount: "€1.4M",
    description:
      "Deputado com participação de 30% numa empresa de consultoria (NovaTech Consulting) que faturou €1.4M ao Ministério da Saúde. Participação não consta do registo de interesses.",
    pattern: "DEPUTADO → PARTICIPAÇÃO OCULTA → CONTRATOS MINISTÉRIO",
    sources: ["Registo Interesses AR", "Registo Comercial", "Portal BASE", "Receita"],
    entities: { politico: "Dep. C.M.", empresa: "NovaTech Consulting", participacao: "30%" },
  },
  {
    id: 7,
    severity: "ALTO",
    score: 79,
    title: "Enriquecimento patrimonial inexplicado",
    subtitle: "Câmara Municipal de Sintra",
    amount: "€780K",
    description:
      "Vereador declarou em 2020 património de €120K. Em 2024, registo predial mostra 3 imóveis novos (valor estimado €780K). Rendimento declarado: €48K/ano.",
    pattern: "DECLARAÇÃO PATRIMÓNIO ↔ REGISTO PREDIAL = DISCREPÂNCIA",
    sources: ["Declarações AR", "Registo Predial", "Portal Finanças"],
    entities: { politico: "Vereador P.S.", imoveis: 3, discrepancia: "€660K" },
  },
  {
    id: 8,
    severity: "ALTO",
    score: 76,
    title: "Rede de subcontratação circular",
    subtitle: "Metro do Porto — Expansão",
    amount: "€4.1M",
    description:
      "Empresa A subcontrata Empresa B, que subcontrata Empresa C, que é detida pelo mesmo beneficiário efetivo da Empresa A. Circuito de faturação sem valor acrescentado real.",
    pattern: "EMPRESA A → B → C → MESMO BENEFICIÁRIO EFETIVO",
    sources: ["Portal BASE", "RCBE", "Registo Comercial"],
    entities: { empresas: ["ConstroiMais", "EngePlus", "Nova Obra"], beneficiario: "H.M." },
  },
  {
    id: 9,
    severity: "MÉDIO",
    score: 68,
    title: "Padrão de adjudicação sazonal",
    subtitle: "Câmara Municipal de Cascais",
    amount: "€1.2M",
    description:
      "85% dos contratos por ajuste direto concentrados nos meses de novembro e dezembro (fim do ano fiscal). Padrão consistente nos últimos 4 anos.",
    pattern: "CONCENTRAÇÃO TEMPORAL → AJUSTES DIRETOS → FIM ANO FISCAL",
    sources: ["Portal BASE", "Compras Públicas"],
    entities: { periodo: "Nov-Dez", percentagem: "85%", anos: 4 },
  },
  {
    id: 10,
    severity: "MÉDIO",
    score: 64,
    title: "Rotação suspeita de fornecedores",
    subtitle: "INEM — Equipamentos",
    amount: "€890K",
    description:
      "3 empresas com morada fiscal no mesmo edifício ganham contratos alternadamente. Sócios-gerentes partilham o mesmo contabilista e advogado.",
    pattern: "MESMA MORADA + MESMO CONTABILISTA = CONLUIO PROVÁVEL",
    sources: ["Portal BASE", "Registo Comercial", "Ordem Contabilistas"],
    entities: { empresas: 3, morada: "Rua X, Lisboa", contratos_total: 12 },
  },
  {
    id: 11,
    severity: "MÉDIO",
    score: 58,
    title: "Atraso sistemático em publicações",
    subtitle: "Câmara Municipal de Braga",
    amount: "€3.4M (opacidade)",
    description:
      "Câmara publica contratos no Portal BASE com atraso médio de 187 dias (obrigatório: 10 dias). 23 contratos ainda não publicados referentes a 2023.",
    pattern: "PUBLICAÇÃO TARDIA → REDUÇÃO ESCRUTÍNIO PÚBLICO",
    sources: ["Portal BASE", "DGAL", "Tribunal de Contas"],
    entities: { atraso_medio: "187 dias", nao_publicados: 23, ano: 2023 },
  },
];

const CROSS_SOURCE = [
  { label: "Empresas NIPC com contratos públicos (BASE)", count: "8.412" },
  { label: "Empresas NIPC com doações a partidos (ECFP)", count: "3.891" },
  { label: "Empresas NIPC com sanções (Tribunal de Contas)", count: "1.247" },
  { label: "Empresas sancionadas que ganharam contratos", count: "189" },
  { label: "Doadores individuais com NIF (CNE/ECFP)", count: "42.563" },
  { label: "Pessoas sancionadas / condenadas", count: "876" },
];

const FONTES = [
  { name: "Portal BASE", type: "Contratos Públicos", status: "online", records: "2.4M" },
  { name: "ECFP / CNE", type: "Financiamento Partidos", status: "online", records: "312K" },
  { name: "Registo Comercial", type: "Empresas / Sócios", status: "online", records: "1.8M" },
  { name: "RCBE", type: "Beneficiários Efetivos", status: "online", records: "890K" },
  { name: "Tribunal de Contas", type: "Auditorias / Sanções", status: "online", records: "45K" },
  { name: "Seg. Social", type: "Vínculos Laborais", status: "parcial", records: "5.1M" },
  { name: "DGAL", type: "Finanças Autárquicas", status: "online", records: "620K" },
  { name: "Transparência AR", type: "Declarações Interesses", status: "online", records: "1.2K" },
  { name: "Registo Predial", type: "Imóveis", status: "parcial", records: "3.2M" },
  { name: "Portal Finanças", type: "Rendimentos", status: "restrito", records: "—" },
  { name: "TED (UE)", type: "Contratos Europeus", status: "online", records: "890K" },
  { name: "OpenCorporates", type: "Empresas UE", status: "online", records: "210M" },
];

function severityColor(s) {
  if (s === "CRÍTICO") return "#ff4444";
  if (s === "ALTO") return "#ff8c00";
  return "#ffd700";
}

function severityBg(s) {
  if (s === "CRÍTICO") return "rgba(255,68,68,0.12)";
  if (s === "ALTO") return "rgba(255,140,0,0.10)";
  return "rgba(255,215,0,0.08)";
}

function AnimatedNumber({ target, duration = 1200 }) {
  const [val, setVal] = useState(0);
  const ref = useRef();
  useEffect(() => {
    const num = parseFloat(target.replace(/[^0-9.]/g, ""));
    if (isNaN(num)) return;
    let start = 0;
    const step = (ts) => {
      if (!ref.current) ref.current = ts;
      const p = Math.min((ts - ref.current) / duration, 1);
      setVal(Math.floor(num * p));
      if (p < 1) requestAnimationFrame(step);
      else setVal(num);
    };
    requestAnimationFrame(step);
  }, [target, duration]);
  return <span>{val.toLocaleString("pt-PT")}</span>;
}

function ScoreBar({ score, color }) {
  const [w, setW] = useState(0);
  useEffect(() => {
    setTimeout(() => setW(score), 100);
  }, [score]);
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
      <div style={{ width: 80, height: 4, background: "rgba(255,255,255,0.08)", borderRadius: 2, overflow: "hidden" }}>
        <div
          style={{
            width: `${w}%`,
            height: "100%",
            background: color,
            borderRadius: 2,
            transition: "width 0.8s cubic-bezier(0.22,1,0.36,1)",
          }}
        />
      </div>
      <span style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 13, color, fontWeight: 600 }}>{score}%</span>
    </div>
  );
}

function InsightCard({ insight, index, expanded, onToggle }) {
  const color = severityColor(insight.severity);
  const bg = severityBg(insight.severity);
  return (
    <div
      onClick={onToggle}
      style={{
        background: expanded ? bg : "rgba(255,255,255,0.02)",
        border: `1px solid ${expanded ? color + "44" : "rgba(255,255,255,0.06)"}`,
        borderLeft: `3px solid ${color}`,
        borderRadius: 8,
        padding: "20px 24px",
        cursor: "pointer",
        transition: "all 0.3s ease",
        animationDelay: `${index * 60}ms`,
        animation: "fadeUp 0.5s ease both",
      }}
    >
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 8 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <span
            style={{
              background: color + "22",
              color,
              fontFamily: "'JetBrains Mono', monospace",
              fontSize: 11,
              fontWeight: 700,
              padding: "3px 10px",
              borderRadius: 4,
              letterSpacing: 1.5,
            }}
          >
            {insight.severity}
          </span>
          <span style={{ color: "rgba(255,255,255,0.4)", fontSize: 12 }}>{insight.subtitle}</span>
        </div>
        <ScoreBar score={insight.score} color={color} />
      </div>
      <h3
        style={{
          fontFamily: "'Space Grotesk', 'JetBrains Mono', monospace",
          fontSize: 18,
          fontWeight: 600,
          color: "#e8e0d4",
          margin: "8px 0 4px",
        }}
      >
        {insight.title}
      </h3>
      <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 15, color: "#c8a84e", fontWeight: 500 }}>
        💰 {insight.amount}
      </div>
      {expanded && (
        <div style={{ marginTop: 16, animation: "fadeUp 0.3s ease both" }}>
          <p style={{ color: "rgba(255,255,255,0.65)", fontSize: 14, lineHeight: 1.7, margin: "0 0 16px" }}>
            {insight.description}
          </p>
          <div
            style={{
              background: "rgba(0,0,0,0.3)",
              borderLeft: `2px solid ${color}55`,
              borderRadius: 4,
              padding: "12px 16px",
              marginBottom: 12,
            }}
          >
            <div
              style={{
                fontFamily: "'JetBrains Mono', monospace",
                fontSize: 10,
                color: "rgba(255,255,255,0.35)",
                letterSpacing: 2,
                marginBottom: 6,
              }}
            >
              PATTERN
            </div>
            <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 13, color, fontWeight: 500 }}>
              {insight.pattern}
            </div>
          </div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
            {insight.sources.map((s) => (
              <span
                key={s}
                style={{
                  fontFamily: "'JetBrains Mono', monospace",
                  fontSize: 11,
                  color: "rgba(255,255,255,0.45)",
                  background: "rgba(255,255,255,0.05)",
                  padding: "4px 10px",
                  borderRadius: 4,
                  border: "1px solid rgba(255,255,255,0.08)",
                }}
              >
                {s}
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

export default function App() {
  // CSV will be fetched from public/resultado.csv
  const [tab, setTab] = useState("insights");
  const [filter, setFilter] = useState("Todos");
  const [expandedId, setExpandedId] = useState(1);
  const [loaded, setLoaded] = useState(false);

  // state for CSV data
  const [contracts, setContracts] = useState([]);
  useEffect(() => {
    setTimeout(() => setLoaded(true), 100);
    // load the pre-converted data
    console.log("loading contractsData length", contractsData.length);
    setContracts(contractsData);
  }, []);

  const filtered =
    filter === "Todos"
      ? INSIGHTS
      : INSIGHTS.filter((i) => i.severity === filter.toUpperCase());

  const totalExposure = "€31.1M";

  const severityCounts = {
    Todos: INSIGHTS.length,
    Crítico: INSIGHTS.filter((i) => i.severity === "CRÍTICO").length,
    Alto: INSIGHTS.filter((i) => i.severity === "ALTO").length,
    Médio: INSIGHTS.filter((i) => i.severity === "MÉDIO").length,
  };

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#0d0f14",
        color: "#e8e0d4",
        fontFamily: "'DM Sans', 'Segoe UI', sans-serif",
        position: "relative",
        overflow: "hidden",
      }}
    >
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600;700&family=Space+Grotesk:wght@400;500;600;700&display=swap');
        @keyframes fadeUp {
          from { opacity: 0; transform: translateY(12px); }
          to { opacity: 1; transform: translateY(0); }
        }
        @keyframes pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.4; }
        }
        @keyframes scanline {
          0% { transform: translateY(-100%); }
          100% { transform: translateY(100vh); }
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.1); border-radius: 3px; }
      `}</style>

      {/* Scanline effect */}
      <div
        style={{
          position: "fixed",
          top: 0,
          left: 0,
          right: 0,
          height: 2,
          background: "linear-gradient(90deg, transparent, rgba(255,68,68,0.15), transparent)",
          animation: "scanline 4s linear infinite",
          pointerEvents: "none",
          zIndex: 100,
        }}
      />

      {/* Grid overlay */}
      <div
        style={{
          position: "fixed",
          inset: 0,
          backgroundImage:
            "linear-gradient(rgba(255,255,255,0.015) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.015) 1px, transparent 1px)",
          backgroundSize: "60px 60px",
          pointerEvents: "none",
          zIndex: 0,
        }}
      />

      <div style={{ position: "relative", zIndex: 1, maxWidth: 1100, margin: "0 auto", padding: "0 24px" }}>
        {/* Header */}
        <header
          style={{
            padding: "32px 0 24px",
            borderBottom: "1px solid rgba(255,255,255,0.06)",
            animation: loaded ? "fadeUp 0.6s ease both" : "none",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 4 }}>
            <div
              style={{
                width: 10,
                height: 10,
                borderRadius: "50%",
                background: "#ff4444",
                boxShadow: "0 0 12px rgba(255,68,68,0.5)",
                animation: "pulse 2s ease infinite",
              }}
            />
            <span
              style={{
                fontFamily: "'JetBrains Mono', monospace",
                fontSize: 11,
                letterSpacing: 3,
                color: "rgba(255,255,255,0.4)",
                fontWeight: 600,
              }}
            >
              LIVE
            </span>
            <span
              style={{
                fontFamily: "'JetBrains Mono', monospace",
                fontSize: 11,
                color: "rgba(255,255,255,0.2)",
                marginLeft: "auto",
              }}
            >
              PROTÓTIPO • DADOS CSV
            </span>
          </div>
          <h1
            style={{
              fontFamily: "'Space Grotesk', sans-serif",
              fontSize: 32,
              fontWeight: 700,
              letterSpacing: -1,
              background: "linear-gradient(135deg, #e8e0d4, #c8a84e)",
              WebkitBackgroundClip: "text",
              WebkitTextFillColor: "transparent",
              marginBottom: 4,
            }}
          >
            Observatório de Integridade
          </h1>
          <p style={{ color: "rgba(255,255,255,0.35)", fontSize: 14 }}>
            Cruzamento automatizado de bases de dados públicas portuguesas para deteção de irregularidades
          </p>
          {contracts.length > 0 && (
            <>
              <p style={{ color: "rgba(255,255,255,0.45)", fontSize: 13, marginTop: 4 }}>
                Dados CSV carregados: {contracts.length.toLocaleString("pt-PT")} linhas
              </p>
              <div style={{ marginTop: 12, color: "#c8a84e", fontSize: 12 }}>
                <strong>Exemplo (5 primeiras linhas):</strong>
                <table style={{ width: "100%", marginTop: 6, fontSize: 11, borderCollapse: "collapse" }}>
                  <thead>
                    <tr>
                      {Object.keys(contracts[0]).slice(0, 5).map((h) => (
                        <th key={h} style={{borderBottom: "1px solid rgba(255,255,255,0.2)", padding: "2px 4px", textAlign: "left"}}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {contracts.slice(0, 5).map((row, idx) => (
                      <tr key={idx}>
                        {Object.values(row).slice(0, 5).map((v, j) => (
                          <td key={j} style={{padding: "2px 4px", borderBottom: "1px solid rgba(255,255,255,0.06)"}}>{v}</td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </header>

        {/* Stats bar */}
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(4, 1fr)",
            gap: 1,
            margin: "24px 0",
            background: "rgba(255,255,255,0.04)",
            borderRadius: 8,
            overflow: "hidden",
            animation: loaded ? "fadeUp 0.6s ease 0.1s both" : "none",
          }}
        >
          {[
            { label: "ENTIDADES", value: "49", color: "#c8a84e" },
            { label: "CONEXÕES", value: "58", color: "#e8e0d4" },
            { label: "FONTES", value: "12", color: "#e8e0d4" },
            { label: "ALERTAS", value: "4", color: "#ff4444" },
          ].map((s) => (
            <div key={s.label} style={{ padding: "16px 20px", textAlign: "center", background: "rgba(0,0,0,0.2)" }}>
              <div
                style={{
                  fontFamily: "'Space Grotesk', monospace",
                  fontSize: 28,
                  fontWeight: 700,
                  color: s.color,
                }}
              >
                {s.value}
              </div>
              <div
                style={{
                  fontFamily: "'JetBrains Mono', monospace",
                  fontSize: 10,
                  letterSpacing: 2,
                  color: "rgba(255,255,255,0.35)",
                  marginTop: 2,
                }}
              >
                {s.label}
              </div>
            </div>
          ))}
        </div>

        {/* Tabs */}
        <div
          style={{
            display: "flex",
            gap: 0,
            borderBottom: "1px solid rgba(255,255,255,0.06)",
            marginBottom: 24,
            animation: loaded ? "fadeUp 0.6s ease 0.15s both" : "none",
          }}
        >
          {["insights", "cruzamentos", "fontes"].map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              style={{
                fontFamily: "'JetBrains Mono', monospace",
                fontSize: 12,
                letterSpacing: 1.5,
                textTransform: "uppercase",
                background: "none",
                border: "none",
                color: tab === t ? "#c8a84e" : "rgba(255,255,255,0.3)",
                borderBottom: tab === t ? "2px solid #c8a84e" : "2px solid transparent",
                padding: "12px 20px",
                cursor: "pointer",
                transition: "all 0.2s ease",
                fontWeight: 600,
              }}
            >
              {t === "insights" ? `Insights ${INSIGHTS.length}` : t === "cruzamentos" ? "Cruzamentos" : "Fontes"}
            </button>
          ))}
        </div>

        {/* Insights Tab */}
        {tab === "insights" && (
          <div style={{ animation: "fadeUp 0.4s ease both" }}>
            {/* Exposure banner */}
            <div
              style={{
                background: "linear-gradient(135deg, rgba(200,168,78,0.08), rgba(255,68,68,0.06))",
                border: "1px solid rgba(200,168,78,0.15)",
                borderLeft: "3px solid #c8a84e",
                borderRadius: 8,
                padding: "24px 28px",
                marginBottom: 24,
              }}
            >
              <div
                style={{
                  fontFamily: "'JetBrains Mono', monospace",
                  fontSize: 10,
                  letterSpacing: 3,
                  color: "#c8a84e",
                  marginBottom: 4,
                }}
              >
                EXPOSIÇÃO TOTAL
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
                <span
                  style={{
                    fontFamily: "'Space Grotesk', monospace",
                    fontSize: 48,
                    fontWeight: 700,
                    color: "#e8e0d4",
                    letterSpacing: -2,
                  }}
                >
                  {totalExposure}
                </span>
                <div style={{ textAlign: "right" }}>
                  <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 13, color: "rgba(255,255,255,0.5)" }}>
                    {INSIGHTS.length} irregularidades
                  </div>
                  <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 13, color: "rgba(255,255,255,0.35)" }}>
                    12 fontes
                  </div>
                </div>
              </div>
            </div>

            {/* Filters */}
            <div style={{ display: "flex", gap: 8, marginBottom: 20 }}>
              {Object.entries(severityCounts).map(([key, count]) => (
                <button
                  key={key}
                  onClick={() => setFilter(key)}
                  style={{
                    fontFamily: "'JetBrains Mono', monospace",
                    fontSize: 12,
                    background: filter === key ? "rgba(255,255,255,0.08)" : "transparent",
                    border: `1px solid ${filter === key ? "rgba(255,255,255,0.15)" : "rgba(255,255,255,0.06)"}`,
                    color: filter === key ? "#e8e0d4" : "rgba(255,255,255,0.35)",
                    padding: "6px 14px",
                    borderRadius: 6,
                    cursor: "pointer",
                    transition: "all 0.2s ease",
                  }}
                >
                  {key} {count}
                </button>
              ))}
            </div>

            {/* Insight cards */}
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {filtered.map((insight, i) => (
                <InsightCard
                  key={insight.id}
                  insight={insight}
                  index={i}
                  expanded={expandedId === insight.id}
                  onToggle={() => setExpandedId(expandedId === insight.id ? null : insight.id)}
                />
              ))}
            </div>
          </div>
        )}

        {/* Cross-source Tab */}
        {tab === "cruzamentos" && (
          <div style={{ animation: "fadeUp 0.4s ease both" }}>
            <h2
              style={{
                fontFamily: "'Space Grotesk', sans-serif",
                fontSize: 20,
                fontWeight: 600,
                marginBottom: 8,
                color: "#e8e0d4",
              }}
            >
              Ligação de entidades via NIF / NIPC
            </h2>
            <p style={{ color: "rgba(255,255,255,0.4)", fontSize: 14, marginBottom: 24 }}>
              Identificador único como chave de cruzamento entre bases de dados
            </p>
            <div
              style={{
                border: "1px solid rgba(255,255,255,0.08)",
                borderRadius: 8,
                overflow: "hidden",
              }}
            >
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "1fr 120px",
                  background: "rgba(255,255,255,0.03)",
                  padding: "12px 20px",
                  borderBottom: "1px solid rgba(255,255,255,0.08)",
                }}
              >
                <span
                  style={{
                    fontFamily: "'JetBrains Mono', monospace",
                    fontSize: 11,
                    letterSpacing: 1.5,
                    color: "rgba(255,255,255,0.4)",
                  }}
                >
                  CRUZAMENTO
                </span>
                <span
                  style={{
                    fontFamily: "'JetBrains Mono', monospace",
                    fontSize: 11,
                    letterSpacing: 1.5,
                    color: "rgba(255,255,255,0.4)",
                    textAlign: "right",
                  }}
                >
                  CONTAGEM
                </span>
              </div>
              {CROSS_SOURCE.map((row, i) => (
                <div
                  key={i}
                  style={{
                    display: "grid",
                    gridTemplateColumns: "1fr 120px",
                    padding: "14px 20px",
                    borderBottom: i < CROSS_SOURCE.length - 1 ? "1px solid rgba(255,255,255,0.04)" : "none",
                    background: i === 3 ? "rgba(255,68,68,0.05)" : "transparent",
                    animation: "fadeUp 0.4s ease both",
                    animationDelay: `${i * 80}ms`,
                  }}
                >
                  <span
                    style={{
                      fontFamily: "'JetBrains Mono', monospace",
                      fontSize: 13,
                      color: i === 3 ? "#e8e0d4" : "rgba(255,255,255,0.6)",
                      fontWeight: i === 3 ? 700 : 400,
                    }}
                  >
                    {row.label}
                  </span>
                  <span
                    style={{
                      fontFamily: "'JetBrains Mono', monospace",
                      fontSize: 14,
                      color: i === 3 ? "#ff4444" : "#c8a84e",
                      fontWeight: 600,
                      textAlign: "right",
                    }}
                  >
                    {row.count}
                  </span>
                </div>
              ))}
            </div>

            {/* Visual diagram */}
            <div
              style={{
                marginTop: 32,
                padding: 24,
                background: "rgba(255,255,255,0.02)",
                border: "1px solid rgba(255,255,255,0.06)",
                borderRadius: 8,
              }}
            >
              <div
                style={{
                  fontFamily: "'JetBrains Mono', monospace",
                  fontSize: 10,
                  letterSpacing: 2,
                  color: "rgba(255,255,255,0.3)",
                  marginBottom: 16,
                }}
              >
                ARQUITETURA DE CRUZAMENTO
              </div>
              <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 13, color: "rgba(255,255,255,0.5)", lineHeight: 2.2 }}>
                <span style={{ color: "#c8a84e" }}>Portal BASE</span> ──── NIPC ────┐{"\n"}
                <span style={{ color: "#c8a84e" }}>ECFP / CNE</span> ──── NIF/NIPC ──┤{"\n"}
                <span style={{ color: "#c8a84e" }}>Reg. Comercial</span> ── NIPC ────┤── <span style={{ color: "#ff4444" }}>CRUZAMENTO</span> ── <span style={{ color: "#e8e0d4" }}>INSIGHTS</span>{"\n"}
                <span style={{ color: "#c8a84e" }}>RCBE</span> ──────────── NIF ─────┤{"\n"}
                <span style={{ color: "#c8a84e" }}>Tribunal Contas</span> ─ NIPC ────┤{"\n"}
                <span style={{ color: "#c8a84e" }}>Seg. Social</span> ──── NISS/NIF ──┘
              </div>
            </div>
          </div>
        )}

        {/* Sources Tab */}
        {tab === "fontes" && (
          <div style={{ animation: "fadeUp 0.4s ease both" }}>
            <h2
              style={{
                fontFamily: "'Space Grotesk', sans-serif",
                fontSize: 20,
                fontWeight: 600,
                marginBottom: 8,
              }}
            >
              Fontes de Dados Conectadas
            </h2>
            <p style={{ color: "rgba(255,255,255,0.4)", fontSize: 14, marginBottom: 24 }}>
              Bases de dados públicas portuguesas e europeias
            </p>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
              {FONTES.map((f, i) => (
                <div
                  key={f.name}
                  style={{
                    padding: "16px 20px",
                    border: "1px solid rgba(255,255,255,0.06)",
                    borderRadius: 8,
                    background: "rgba(255,255,255,0.02)",
                    animation: "fadeUp 0.4s ease both",
                    animationDelay: `${i * 50}ms`,
                  }}
                >
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 6 }}>
                    <span style={{ fontWeight: 600, fontSize: 14, color: "#e8e0d4" }}>{f.name}</span>
                    <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                      <div
                        style={{
                          width: 7,
                          height: 7,
                          borderRadius: "50%",
                          background:
                            f.status === "online" ? "#44ff88" : f.status === "parcial" ? "#ffd700" : "#ff4444",
                          boxShadow: `0 0 6px ${f.status === "online" ? "rgba(68,255,136,0.4)" : f.status === "parcial" ? "rgba(255,215,0,0.4)" : "rgba(255,68,68,0.4)"}`,
                        }}
                      />
                      <span
                        style={{
                          fontFamily: "'JetBrains Mono', monospace",
                          fontSize: 10,
                          color: "rgba(255,255,255,0.35)",
                          textTransform: "uppercase",
                        }}
                      >
                        {f.status}
                      </span>
                    </div>
                  </div>
                  <div style={{ display: "flex", justifyContent: "space-between" }}>
                    <span
                      style={{
                        fontFamily: "'JetBrains Mono', monospace",
                        fontSize: 11,
                        color: "rgba(255,255,255,0.35)",
                      }}
                    >
                      {f.type}
                    </span>
                    <span
                      style={{
                        fontFamily: "'JetBrains Mono', monospace",
                        fontSize: 12,
                        color: "#c8a84e",
                      }}
                    >
                      {f.records} registos
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Footer */}
        <footer
          style={{
            padding: "40px 0 24px",
            borderTop: "1px solid rgba(255,255,255,0.04)",
            marginTop: 48,
            textAlign: "center",
          }}
        >
          <div
            style={{
              fontFamily: "'JetBrains Mono', monospace",
              fontSize: 10,
              letterSpacing: 2,
              color: "rgba(255,255,255,0.2)",
            }}
          >
            OBSERVATÓRIO DE INTEGRIDADE • PROTÓTIPO • DADOS CARREGADOS DO CSV
          </div>
          <div
            style={{
              fontFamily: "'JetBrains Mono', monospace",
              fontSize: 10,
              color: "rgba(255,255,255,0.15)",
              marginTop: 4,
            }}
          >
            Fontes reais: Portal BASE • ECFP/CNE • Registo Comercial • RCBE • Tribunal de Contas • DGAL • TED/UE
          </div>
        </footer>
      </div>
    </div>
  );
}
