module RegistoComercialFixtures
  SEARCH_RESULTS_HTML = <<~HTML
    <html><body>
      <table>
        <tr>
          <td>509999001</td>
          <td>Construções Ferreira Lda</td>
          <td>2024-01-15</td>
          <td>Registo Comercial</td>
          <td><a href="/DetalhePublicacao.aspx?id=123">Ver</a></td>
        </tr>
        <tr>
          <td>509999001</td>
          <td>Construções Ferreira Lda</td>
          <td>2023-05-20</td>
          <td>Avisos</td>
          <td><a href="/DetalhePublicacao.aspx?id=456">Ver</a></td>
        </tr>
      </table>
    </body></html>
  HTML

  DETAIL_HTML = <<~HTML
    <html><body>
      <table>
        <tr><td>NIPC</td><td>509999001</td></tr>
        <tr><td>Firma</td><td>Construções Ferreira Lda</td></tr>
        <tr><td>Data de publicação</td><td>2024-01-15</td></tr>
        <tr><td>Sede</td><td>Rua das Obras 10, Porto</td></tr>
        <tr><td>Capital Social</td><td>50.000 EUR</td></tr>
        <tr><td>Natureza Jurídica</td><td>Sociedade por Quotas</td></tr>
      </table>
      <div id="lblConteudo">
        Sócios: João Ferreira, NIF 123456789, com a quota de 50%.
        Gerentes: Maria Silva, residente em Porto.
      </div>
    </body></html>
  HTML

  HIDDEN_FIELDS_HTML = <<~HTML
    <html><body>
      <form>
        <input type="hidden" name="__VIEWSTATE" value="abc123" />
        <input type="hidden" name="__EVENTVALIDATION" value="xyz789" />
      </form>
    </body></html>
  HTML

  POSTBACK_HTML = <<~HTML
    <html><body>
      <table>
        <tr>
          <td>509999001</td><td>Empresa Teste</td><td>2024-01-01</td><td>Avisos</td>
          <td><a href="javascript:__doPostBack('DetalhePublicacao','select$0')">Ver</a></td>
        </tr>
      </table>
    </body></html>
  HTML

  GRIDVIEW_HTML = <<~HTML
    <html><body>
      <table id="GridView1">
        <tr>
          <td>509999001</td><td>Grid Empresa</td><td>2024-03-01</td><td>Avisos</td>
          <td><a href="/DetalhePublicacao.aspx?id=789">Ver</a></td>
        </tr>
      </table>
    </body></html>
  HTML

  FALLBACK_LINKS_HTML = <<~HTML
    <html><body>
      <a href="/DetalhePublicacao.aspx?id=999">Publicação Avulsa</a>
    </body></html>
  HTML

  EMPTY_ROWS_HTML = <<~HTML
    <html><body>
      <table><tr><td></td><td></td></tr></table>
    </body></html>
  HTML

  # GridView fallback: no <table> in document, but GridView-id div contains
  # tr elements (non-standard HTML that Nokogiri handles), triggering the
  # GridView fallback path in extrair_resultados.
  GRIDVIEW_FALLBACK_HTML = <<~HTML
    <html><body>
      <div id="GridView1">
        <tr>
          <td>509999002</td><td>Grid Empresa</td><td>2024-03-01</td><td>Avisos</td>
          <td><a href="/DetalhePublicacao.aspx?id=789">Ver</a></td>
        </tr>
      </div>
    </body></html>
  HTML

  DETAIL_EXTENDED_HTML = <<~HTML
    <html><body>
      <table>
        <tr><td>Distrito</td><td>Porto</td></tr>
        <tr><td>Concelho</td><td>Matosinhos</td></tr>
        <tr><td>Objecto</td><td>Prestação de serviços</td></tr>
      </table>
    </body></html>
  HTML

  CORPO_FALLBACK_HTML = <<~HTML
    <html><body>
      <p>short</p>
      <div>Esta é uma descrição muito longa sobre sócios e gerentes da empresa. Sócios: Ana Lopes, NIF 987654321, com quota de 100%. Gerentes: Bruno Costa, residente em Lisboa e com plenos poderes de gestão da sociedade comercial.</div>
    </body></html>
  HTML
end
