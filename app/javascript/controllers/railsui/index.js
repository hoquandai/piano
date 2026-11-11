        import { application } from "controllers/application"
        import {
          RailsuiClipboard,
          RailsuiCountUp,
          RailsuiCombobox,
          RailsuiDateRangePicker,
          RailsuiDropdown,
          RailsuiModal,
          RailsuiRange,
          RailsuiReadMore,
          RailsuiSelectAll,
          RailsuiTabs,
          RailsuiToast,
          RailsuiToggle,
          RailsuiTooltip
        } from "railsui-stimulus"

        // Register railsui-stimulus components
        application.register("railsui-clipboard", RailsuiClipboard)
        application.register("railsui-count-up", RailsuiCountUp)
        application.register("railsui-combobox", RailsuiCombobox)
        application.register("railsui-date-range-picker", RailsuiDateRangePicker)
        application.register("railsui-dropdown", RailsuiDropdown)
        application.register("railsui-modal", RailsuiModal)
        application.register("railsui-range", RailsuiRange)
        application.register("railsui-read-more", RailsuiReadMore)
        application.register("railsui-select-all", RailsuiSelectAll)
        application.register("railsui-tabs", RailsuiTabs)
        application.register("railsui-toast", RailsuiToast)
        application.register("railsui-toggle", RailsuiToggle)
        application.register("railsui-tooltip", RailsuiTooltip)

        // Register theme-specific controllers
        import ComboSelectController from "controllers/railsui/combo_select_controller"
application.register("combo-select", ComboSelectController)
import DashboardController from "controllers/railsui/dashboard_controller"
application.register("dashboard", DashboardController)
import NavController from "controllers/railsui/nav_controller"
application.register("nav", NavController)
