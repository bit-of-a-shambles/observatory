class DashboardController < ApplicationController
  include ActionView::Helpers::NumberHelper

  def index
    @stats = [
      { label: "CONTRATOS", value: number_with_delimiter(Contract.count),  color: "text-[#c8a84e]" },
      { label: "ENTIDADES", value: number_with_delimiter(Entity.count),     color: "text-[#e8e0d4]" },
      { label: "FONTES",    value: DataSource.where(status: :active).count, color: "text-[#e8e0d4]" },
      { label: "ALERTAS",   value: "0",                                      color: "text-[#ff4444]" }
    ]

    @sources = DataSource.order(:country_code, :name).map do |ds|
      {
        name:       ds.name,
        country:    ds.country_code,
        type:       ds.source_type.capitalize,
        status:     ds.status,
        records:    number_with_delimiter(ds.record_count),
        synced_at:  ds.last_synced_at&.strftime("%Y-%m-%d %H:%M")
      }
    end

    # Sample insight cards — rule-based engine is Phase 2.
    # These will be replaced by computed red flags once the scoring layer exists.
    @insights = [
      {
        id: 1, severity: "CRÍTICO", score: 97, title: "Auto-direcionamento de emendas",
        subtitle: "Câmara Municipal de Gondomar", amount: "€12.3M",
        description: "Autarca destinou €12.3M em contratos públicos para a Construções Ferreira & Filhos, Lda. (NIPC 509XXX123), empresa detida pelo cunhado. 73% dos contratos foram por ajuste direto, abaixo do limiar de €20k.",
        pattern: "AUTARCA → AJUSTES DIRETOS → EMPRESA FAMILIAR",
        sources: ["Portal BASE", "Registo Comercial", "DGAL", "Tribunal de Contas"]
      },
      {
        id: 2, severity: "CRÍTICO", score: 94, title: "Funcionários fantasma",
        subtitle: "Junta de Freguesia de Benfica", amount: "~€890K/ano",
        description: "Cruzamento Segurança Social × servidores municipais: 21 pessoas simultaneamente empregadas na Limpezas Atlântico, Lda. e funcionários da Junta de Freguesia de Benfica.",
        pattern: "SEG. SOCIAL EMPRESA × FOLHA AUTARQUIA = DUPLO VÍNCULO",
        sources: ["Seg. Social", "Transparência Autárquica", "Registo Comercial"]
      },
      {
        id: 3, severity: "ALTO", score: 85, title: "Fragmentação de contratos",
        subtitle: "Câmara Municipal de Oeiras", amount: "€2.8M",
        description: "47 contratos por ajuste direto à mesma empresa (MediaPro Comunicação) num período de 18 meses, todos abaixo de €20K. Valor agregado: €2.8M.",
        pattern: "47× AJUSTE DIRETO < €20K → MESMA EMPRESA = €2.8M",
        sources: ["Portal BASE", "Compras Públicas"]
      }
    ]

    @crossings = [
      { label: "Entidades com contratos na base de dados",        count: number_with_delimiter(Entity.where(is_public_body: false).count) },
      { label: "Entidades adjudicantes na base de dados",         count: number_with_delimiter(Entity.where(is_public_body: true).count) },
      { label: "Empresas NIPC com doações a partidos (ECFP)",     count: "—" },
      { label: "Empresas NIPC com sanções (Tribunal de Contas)",  count: "—" }
    ]
  end
end
