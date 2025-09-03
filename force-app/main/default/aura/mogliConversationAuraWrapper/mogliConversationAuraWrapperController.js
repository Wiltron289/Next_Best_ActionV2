({
    init : function(component, event, helper) {
        helper.loadOpportunityId(component);
        // Prefer immediate server resolve for App pages
        helper.resolveFromServerNow(component);
        // Keep LMS/DOM listeners as passive secondary sources
        helper.subscribeToOpportunityContext(component);
        helper.scheduleServerFallback(component);
        try {
            component._nbaHandler = function(e){
                try {
                    var detail = e && e.detail ? e.detail : null;
                    var oppId = detail && detail.recordId ? detail.recordId : null;
                    if (oppId) {
                        component.set("v.opportunityId", oppId);
                        helper.resolveFromOpportunity(component, oppId);
                    }
                } catch(ex) {}
            };
            window.addEventListener('nbaopportunitychange', component._nbaHandler);
            component._leadHandler = function(e){
                try {
                    var detail = e && e.detail ? e.detail : null;
                    var leadId = detail && detail.recordId ? detail.recordId : null;
                    if (leadId) {
                        component.set("v.personRecordId", leadId);
                        helper.forceRerender(component);
                    }
                } catch(ex) {}
            };
            window.addEventListener('nbaleadchange', component._leadHandler);
        } catch(ex) {}
    },

    handleRecordUpdated : function(component, event, helper) {
        helper.loadOpportunityId(component);
    },

    cleanup : function(component, event, helper) {
        helper.unsubscribe(component);
        try {
            if (component._nbaHandler) {
                window.removeEventListener('nbaopportunitychange', component._nbaHandler);
                component._nbaHandler = null;
            }
            if (component._leadHandler) {
                window.removeEventListener('nbaleadchange', component._leadHandler);
                component._leadHandler = null;
            }
        } catch(ex) {}
    }
})
