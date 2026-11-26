import Cocoa

// TODO: @2h4u create and add icon (app icon and menubar icon)

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuController = MenuController()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        FileHandler.createWallpaperFolderIfNeeded()
        
        let updateManager = UpdateManager()
        updateManager.delegate = menuController
        updateManager.start()
        
        menuController.updateManager = updateManager
        menuController.setup()

        // A login-item launch must stay silent in the menu bar; only a
        // launch the user started shows the Settings window.
        if launchedAsLoginItem == false {
            menuController.showSettingsWc(sender: nil)
        }

        Task {
            await AppUpdateManager.checkForUpdate()
        }
    }
    
    /// `true` when macOS launched the app as a login item (the open
    /// application Apple event then carries the
    /// `keyAELaunchedAsLogInItem` parameter).
    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else {
            return false
        }
        return event.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Activating the already running app (Dock or Finder icon click)
        // brings Settings up, like a manual launch. Becoming active by
        // itself (e.g. after a login-item launch) must not.
        if flag == false {
            menuController.showSettingsWc(sender: nil)
        }
        return false
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // MARK: - Core Data Saving and Undo support
    
    @IBAction func saveAction(_ sender: AnyObject?) {
        // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
        let context = Database.instance.persistentContainer.viewContext
        
        if !context.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing before saving")
        }
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Customize this code block to include application-specific recovery steps.
                NSApplication.shared.presentError(error as NSError)
            }
        }
    }
    
    func windowWillReturnUndoManager(window: NSWindow) -> UndoManager? {
        // Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
        return Database.instance.persistentContainer.viewContext.undoManager
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Save changes in the application's managed object context before the application terminates.
        let context = Database.instance.persistentContainer.viewContext
        
        if !context.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing to terminate")
            return .terminateCancel
        }
        
        if !context.hasChanges {
            return .terminateNow
        }
        
        do {
            try context.save()
        } catch {
            // Customize this code block to include application-specific recovery steps.
            let result = sender.presentError(error as NSError)
            if result {
                return .terminateCancel
            }
            
            let question = NSLocalizedString("Could not save changes while quitting. Quit anyway?", comment: "Quit without saves error question message")
            let info = NSLocalizedString("Quitting now will lose any changes you have made since the last successful save", comment: "Quit without saves error question info")
            let quitButton = NSLocalizedString("Quit anyway", comment: "Quit anyway button title")
            let cancelButton = NSLocalizedString("Cancel", comment: "Cancel button title")
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = info
            alert.addButton(withTitle: quitButton)
            alert.addButton(withTitle: cancelButton)
            
            let answer = alert.runModal()
            if answer == .alertSecondButtonReturn {
                return .terminateCancel
            }
        }
        // If we got here, it is time to quit.
        return .terminateNow
    }
}
