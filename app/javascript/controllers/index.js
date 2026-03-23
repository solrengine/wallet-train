import { application } from "./application"

// Shared controllers from @solrengine/wallet-utils
import { WalletController, AutoRefreshController, ClipboardController } from "@solrengine/wallet-utils/controllers"
application.register("wallet", WalletController)
application.register("auto-refresh", AutoRefreshController)
application.register("clipboard", ClipboardController)

// App-specific controllers
import DonateController from "./donate_controller"
application.register("donate", DonateController)

import TransferController from "./transfer_controller"
application.register("transfer", TransferController)
