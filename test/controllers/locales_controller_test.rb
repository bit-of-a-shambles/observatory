require "test_helper"

class LocalesControllerTest < ActionDispatch::IntegrationTest
  test "switches to pt and redirects" do
    get set_locale_path(locale: "pt")
    assert_redirected_to root_path
    assert_equal "pt", session[:locale]
  end

  test "switches to en and redirects" do
    get set_locale_path(locale: "en")
    assert_redirected_to root_path
    assert_equal "en", session[:locale]
  end

  test "ignores unknown locale" do
    get set_locale_path(locale: "xx")
    assert_redirected_to root_path
    assert_nil session[:locale]
  end

  test "dashboard renders in portuguese when locale is pt" do
    get set_locale_path(locale: "pt")
    get root_url
    assert_response :success
    assert_match "CONTRATOS", response.body
    assert_match "AO VIVO",   response.body
  end

  test "dashboard renders in english when locale is en" do
    get set_locale_path(locale: "en")
    get root_url
    assert_response :success
    assert_match "CONTRACTS", response.body
    assert_match "LIVE",      response.body
  end

  test "contracts index renders in portuguese" do
    get set_locale_path(locale: "pt")
    get contracts_url
    assert_response :success
    assert_match "Contratos Públicos", response.body
  end

  test "contracts index renders in english" do
    get set_locale_path(locale: "en")
    get contracts_url
    assert_response :success
    assert_match "Public Contracts", response.body
  end
end
