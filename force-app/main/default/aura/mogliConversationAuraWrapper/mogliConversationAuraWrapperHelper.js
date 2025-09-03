({
    loadOpportunityId : function(component) {
        var simpleRecord = component.get("v.simpleRecord");
        if (simpleRecord && simpleRecord.Lead__c) {
            component.set("v.opportunityId", null);
            component.set("v.personRecordId", simpleRecord.Lead__c);
            this.forceRerender(component);
            return;
        }
        if (simpleRecord && simpleRecord.Opportunity__c) {
            component.set("v.opportunityId", simpleRecord.Opportunity__c);
            this.resolvePersonRecordId(component, simpleRecord.Opportunity__c);
        } else {
            component.set("v.opportunityId", null);
            component.set("v.personRecordId", null);
        }
    },

    resolvePersonRecordId : function(component, opportunityId) {
        if (!opportunityId) { component.set("v.personRecordId", null); return; }
        this.resolveFromOpportunity(component, opportunityId);
    },

    resolveFromOpportunity : function(component, opportunityId) {
        var action = component.get("c.getOpportunityPrimaryContact");
        if (!action) { component.set("v.personRecordId", null); return; }
        action.setParams({ opportunityId: opportunityId });
        action.setCallback(this, function(resp){
            var state = resp.getState();
            if (state === "SUCCESS") {
                var data = resp.getReturnValue();
                var personId = data && data.contactId ? data.contactId : null;
                if (personId) {
                    component.set("v.personRecordId", personId);
                    this.forceRerender(component);
                } else {
                    this.resolveAccountPrimaryFromOpp(component, opportunityId);
                }
            } else {
                this.resolveAccountPrimaryFromOpp(component, opportunityId);
            }
        });
        $A.enqueueAction(action);
    },

    resolveAccountPrimaryFromOpp : function(component, opportunityId) {
        var getAcc = component.get("c.getAccountIdForOpportunity");
        if (!getAcc) { component.set("v.personRecordId", null); return; }
        getAcc.setParams({ opportunityId: opportunityId });
        getAcc.setCallback(this, function(r){
            if (r.getState() === "SUCCESS") {
                var accId = r.getReturnValue();
                if (accId) {
                    var getPrimary = component.get("c.getAccountPrimaryContact");
                    getPrimary.setParams({ accountId: accId });
                    getPrimary.setCallback(this, function(r2){
                        if (r2.getState() === "SUCCESS") {
                            var data = r2.getReturnValue();
                            var cid = data && data.contactId ? data.contactId : null;
                            if (cid) {
                                component.set("v.personRecordId", cid);
                                this.forceRerender(component);
                            } else {
                                this.resolveFromQueueBestPerson(component);
                            }
                        } else {
                            this.resolveFromQueueBestPerson(component);
                        }
                    });
                    $A.enqueueAction(getPrimary);
                } else {
                    this.resolveFromQueueBestPerson(component);
                }
            } else {
                this.resolveFromQueueBestPerson(component);
            }
        });
        $A.enqueueAction(getAcc);
    },

    resolveFromQueueBestPerson : function(component) {
        var recId = component.get("v.recordId");
        if (!recId) { component.set("v.personRecordId", null); return; }
        var a = component.get("c.getQueueBestPerson");
        if (!a) { component.set("v.personRecordId", null); return; }
        a.setParams({ queueItemId: recId });
        a.setCallback(this, function(r){
            if (r.getState() === "SUCCESS") {
                var cid = r.getReturnValue();
                component.set("v.personRecordId", cid);
                if (cid) {
                    this.forceRerender(component);
                }
            } else {
                component.set("v.personRecordId", null);
            }
        });
        $A.enqueueAction(a);
    },

    subscribeToOpportunityContext : function(component) {
        try {
            var messageService = component.find("messageService");
            var channel = component.find("opportunityContext");
            if (!messageService || !channel) { return; }
            var subscription = messageService.subscribe(channel, $A.getCallback(function(message) {
                try {
                    var oppId = null;
                    if (message && typeof message.getParam === 'function') {
                        var payload = message.getParam('payload');
                        if (payload && payload.recordId) { oppId = payload.recordId; }
                    }
                    if (!oppId && message && message.payload && message.payload.recordId) { oppId = message.payload.recordId; }
                    if (!oppId && message && message.recordId) { oppId = message.recordId; }
                    if (oppId) {
                        component.set("v.opportunityId", oppId);
                        this.forceRerender(component);
                        this.resolveFromOpportunity(component, oppId);
                    }
                } catch (e) {}
            }.bind(this)));
            component.set("v.subscription", subscription);
        } catch (e) {}
    },

    scheduleServerFallback : function(component) {
        try {
            window.setTimeout($A.getCallback(function(){
                try {
                    var oppId = component.get("v.opportunityId");
                    var personId = component.get("v.personRecordId");
                    var testId = component.get("v.testRecordId");
                    if (!oppId && !personId && !testId) {
                        var userId = $A.get("$SObjectType.CurrentUser.Id");
                        var action = component.get("c.getNextQueueItemWithDetails");
                        action.setParams({ userId: userId });
                        action.setCallback(this, function(r){
                            if (r.getState() === "SUCCESS") {
                                var res = r.getReturnValue();
                                var qi = res && res.queueItem ? res.queueItem : null;
                                var leadId = qi && qi.Lead__c ? qi.Lead__c : null;
                                if (leadId) {
                                    component.set("v.personRecordId", leadId);
                                    this.forceRerender(component);
                                } else {
                                    var oid = qi && qi.Opportunity__c ? qi.Opportunity__c : null;
                                    if (oid) {
                                        component.set("v.opportunityId", oid);
                                        this.forceRerender(component);
                                        this.resolveFromOpportunity(component, oid);
                                    }
                                }
                            }
                        });
                        $A.enqueueAction(action);
                    }
                } catch(e) {}
            }), 1200);
        } catch (e) {}
    },

    unsubscribe : function(component) {
        try {
            var messageService = component.find("messageService");
            var sub = component.get("v.subscription");
            if (messageService && sub) {
                messageService.unsubscribe(sub);
            }
        } catch (e) {}
    },

    resolveFromServerNow : function(component) {
        try {
            var oppId = component.get("v.opportunityId");
            var personId = component.get("v.personRecordId");
            var testId = component.get("v.testRecordId");
            if (!oppId && !personId && !testId) {
                var userId = $A.get("$SObjectType.CurrentUser.Id");
                var action = component.get("c.getNextQueueItemWithDetails");
                action.setParams({ userId: userId });
                action.setCallback(this, function(r){
                    if (r.getState() === "SUCCESS") {
                        var res = r.getReturnValue();
                        var qi = res && res.queueItem ? res.queueItem : null;
                        var leadId = qi && qi.Lead__c ? qi.Lead__c : null;
                        if (leadId) {
                            component.set("v.personRecordId", leadId);
                            this.forceRerender(component);
                        } else {
                            var oid = qi && qi.Opportunity__c ? qi.Opportunity__c : null;
                            if (oid) {
                                component.set("v.opportunityId", oid);
                                this.forceRerender(component);
                                this.resolveFromOpportunity(component, oid);
                            }
                        }
                    }
                });
                $A.enqueueAction(action);
            }
        } catch (e) {}
    }
    ,
    forceRerender : function(component) {
        try {
            component.set("v.mogliVisible", false);
            var newKey = "refresh_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9);
            component.set("v.refreshKey", newKey);
            window.setTimeout($A.getCallback(function(){
                if (component.isValid()) {
                    component.set("v.mogliVisible", true);
                }
            }), 500);
        } catch(e) {
            console.error("Error in forceRerender:", e);
        }
    }
})
