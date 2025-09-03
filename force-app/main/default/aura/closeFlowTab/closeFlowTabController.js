({
    init : function(component, event, helper) {
        var workspace = component.find("workspace");
        if (!workspace) { component.set("v.status", "Workspace API not available"); return; }
        var delay = component.get("v.delayMs") || 700;
        component.set("v.status", "Checking console context...");

        // Watchdog fallback: if nothing updates after delay+500ms, attempt a direct close
        window.setTimeout($A.getCallback(function(){
            var status = component.get("v.status");
            if (status && status.indexOf("Attempting close") !== -1) {
                // normal path is running
                return;
            }
            if (status && status.indexOf("Closing ") !== -1) {
                return;
            }
            component.set("v.status", "Watchdog: attempting direct tab close...");
            workspace.getFocusedTabInfo().then(function(tabInfo){
                var tabId = tabInfo && tabInfo.tabId ? tabInfo.tabId : null;
                if (tabId) {
                    component.set("v.status", "Watchdog: closing focused tab " + tabId + "...");
                    workspace.closeTab({ tabId: tabId });
                } else {
                    workspace.getEnclosingTabId().then(function(enclosingTabId){
                        component.set("v.status", "Watchdog: closing enclosing tab " + enclosingTabId + "...");
                        workspace.closeTab({ tabId: enclosingTabId });
                    }).catch(function(){ /* no-op */ });
                }
            }).catch(function(){
                workspace.getEnclosingTabId().then(function(enclosingTabId){
                    component.set("v.status", "Watchdog: closing enclosing tab " + enclosingTabId + "...");
                    workspace.closeTab({ tabId: enclosingTabId });
                }).catch(function(){ /* no-op */ });
            });
        }), delay + 500);
        try {
            workspace.isConsoleNavigation().then(function(isConsole){
                component.set("v.status", "Console detected=" + isConsole + ". Attempting close in " + delay + "ms...");
                window.setTimeout($A.getCallback(function(){
                    // Try focused tab first
                    workspace.getFocusedTabInfo().then(function(tabInfo){
                        var tabId = tabInfo && tabInfo.tabId ? tabInfo.tabId : null;
                        if (tabId) {
                            component.set("v.status", "Closing focused tab " + tabId + "...");
                            workspace.closeTab({ tabId: tabId }).then(function(){
                                component.set("v.status", "Close requested for tab " + tabId + ".");
                            }).catch(function(err){ component.set("v.status", "Close failed for focused tab: " + err); });
                        } else {
                            component.set("v.status", "Focused tabId missing, trying enclosing tab...");
                            workspace.getEnclosingTabId().then(function(enclosingTabId){
                                component.set("v.status", "Closing enclosing tab " + enclosingTabId + "...");
                                workspace.closeTab({ tabId: enclosingTabId }).then(function(){
                                    component.set("v.status", "Close requested for enclosing tab " + enclosingTabId + ".");
                                }).catch(function(err){ component.set("v.status", "Close failed for enclosing tab: " + err); });
                            }).catch(function(err){ component.set("v.status", "Unable to determine tab id: " + err); });
                        }
                    }).catch(function(err){
                        component.set("v.status", "Focused tab check failed: " + err + "; trying enclosing tab...");
                        workspace.getEnclosingTabId().then(function(enclosingTabId){
                            component.set("v.status", "Closing enclosing tab " + enclosingTabId + "...");
                            workspace.closeTab({ tabId: enclosingTabId }).then(function(){
                                component.set("v.status", "Close requested for enclosing tab " + enclosingTabId + ".");
                            }).catch(function(e2){ component.set("v.status", "Close failed for enclosing tab: " + e2); });
                        }).catch(function(e3){ component.set("v.status", "Unable to determine tab id: " + e3); });
                    });
                }), delay);
            }).catch(function(err){ component.set("v.status", "Failed to check console context: " + err); });
        } catch (e) {
            component.set("v.status", "Exception: " + e);
        }
    }
})


