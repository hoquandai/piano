require "test_helper"

class ToolsNavigationTest < ActionDispatch::IntegrationTest
  test "tools is listed next to dashboard and opens a blank page" do
    get rui_dashboard_path
    assert_response :success
    assert_select "nav ul > li > a", text: "Tools", href: rui_tools_path

    get rui_tools_path
    assert_response :success
    assert_select "h1", text: "Tools"
    assert_select "form[data-turbo='false'][method=post]"
  end

  test "conversion requires a PDF upload" do
    post rui_tools_convert_path

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Choose a PDF file to convert/
  end
end
