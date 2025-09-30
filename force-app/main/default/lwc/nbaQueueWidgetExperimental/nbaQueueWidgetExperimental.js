import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { publish, MessageContext } from 'lightning/messageService';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadStyle } from 'lightning/platformResourceLoader';
import PlusJakartaSans from '@salesforce/resourceUrl/PlusJakartaSans';
import getNextQueueItemWithDetails from '@salesforce/apex/NBAQueueManager.getNextQueueItemWithDetails';
import getUpNextItem from '@salesforce/apex/NBAQueueManager.getUpNextItem';
import getActivities from '@salesforce/apex/NBAQueueManager.getActivities';
import listNotSurfacedItems from '@salesforce/apex/NBAQueueManager.listNotSurfacedItems';
import markAsViewed from '@salesforce/apex/NBAQueueManager.markAsViewed';
import acceptAction from '@salesforce/apex/NBAQueueManager.acceptAction';
import dismissAction from '@salesforce/apex/NBAQueueManager.dismissAction';
import snoozeQueueItem from '@salesforce/apex/NBAQueueManager.snoozeQueueItem';
import updateCallDisposition from '@salesforce/apex/NBAQueueManager.updateCallDispositionWithQueueId';
import updateCallDispositionWithQueueIdOptions from '@salesforce/apex/NBAQueueManager.updateCallDispositionWithQueueIdOptions';
import cancelCallDisposition from '@salesforce/apex/NBAQueueManager.cancelCallDisposition';
import resolvePrimaryContactForQueueItem from '@salesforce/apex/NBAQueueManager.resolvePrimaryContactForQueueItem';
import getAccountPrimaryContact from '@salesforce/apex/NBAQueueManager.getAccountPrimaryContact';
import getAccountPhoneNumber from '@salesforce/apex/NBAQueueManager.getAccountPhoneNumber';
import getAccountContacts from '@salesforce/apex/NBAQueueManager.getAccountContacts';
import updateQueueItem from '@salesforce/apex/NBAQueueManager.updateQueueItem';
import saveNextSteps from '@salesforce/apex/NBAQueueManager.saveNextSteps';
import saveNextStepsWithLead from '@salesforce/apex/NBAQueueManager.saveNextStepsWithLead';
import saveFutureFollowUp from '@salesforce/apex/NBAQueueManager.saveFutureFollowUp';
import getFutureFollowUpReasons from '@salesforce/apex/NBAQueueManager.getFutureFollowUpReasons';
import getLeadStatusNames from '@salesforce/apex/NBAQueueManager.getLeadStatusNames';
import finalizeQueueItem from '@salesforce/apex/NBAQueueManager.finalizeQueueItem';
import handleEmailAccept from '@salesforce/apex/NBAQueueManager.handleEmailAccept';
import handleEventAccept from '@salesforce/apex/NBAQueueManager.handleEventAccept';
import saveMeetingDisposition from '@salesforce/apex/NBAQueueManager.saveMeetingDisposition';
import completeEmailAction from '@salesforce/apex/NBAQueueManager.completeEmailAction';
import userId from '@salesforce/user/Id';
import OpportunityContextChannel from '@salesforce/messageChannel/NBA_OpportunityContext__c';

export default class NbaQueueWidgetExperimental extends NavigationMixin(LightningElement) {
    // Flow API names (ensure these match your Flow API Names exactly)
    FLOW_API_PROJECT_INITIATION = 'Project_Initiation_Wizard';
    FLOW_API_CLOSED_LOST = 'Closed_Lost_Screen_Flow';
    @api panelHeight = 400;
    @api navigateOnAccept = false; // control auto-navigation after accept - will be set to true via metadata
    @track queueItem = null;
    @track isLoading = false;
    @track showCallDispositionModal = false;
    @track showDismissModal = false;
    @track selectedItem = null;
    @track currentTaskId = null;
    @track callDisposition = '';
    @track callNotes = '';
    @track dismissReason = '';
    @track dismissalCategory = '';
    @track snoozeScheduledAt = '';
    @track currentPhoneNumber = '';
    @track activeTab = 'contact';
    @track upNextItem = null;
    @track notSurfaced = [];
    @track opportunityPrimaryContact = null;
    @track lastRefreshTime = null;
    @track fontLoaded = false;
    @track showCallDispositionForm = false;
    @track showDismissForm = false;
    // Removed embedded flow modal state
    @track pendingAction = null; // Track pending action for when widget is minimized
    @track isBlinking = false; // For alerting when new action comes in
    @track nextStepDate = '';
    @track nextSteps = '';
    @track futureFollowUpDate = '';
    @track futureFollowUpReason = '';
    @track leadStatusOptions = [];
    @track futureFollowUpReasonOptions = [];

    // Refresh functionality
    @track lastRefreshTime = null;
    refreshTimer = null;
    refreshInterval = 300000; // 5 minutes
    @track refreshCountdown = 300; // seconds remaining
    countdownTimer = null;

    // Experimental: Contact confirmation modal state
    @track showContactConfirmationModal = false;
    @track isInContactSelectionMode = false;
    @track selectedContactId = '';
    @track selectedPhoneNumber = '';
    @track availableContacts = [];
    @track availablePhoneNumbers = [];
    @track selectedContactName = '';
    @track selectedPhoneDisplay = '';
    @track showManualPhoneInput = false;
    @track manualPhoneNumber = '';

    // Email and Event action modals
    @track showEmailCompleteModal = false;
    @track showMeetingDispositionModal = false;
    @track meetingDisposition = '';
    @track meetingNotes = '';
    @track navigatedToEmailMessage = false;

    // Embedded flow state
    @track showEmbeddedFlow = false;
    embeddedFlowApiName;
    embeddedFlowRecordId;
    embeddedFlowQueueItemId;
    
    @wire(MessageContext) messageContext;
    _lastPublishedOppId = null;

    @wire(getFutureFollowUpReasons)
    wiredFfuReasons({ error, data }) {
        if (data) {
            this.futureFollowUpReasonOptions = (data || []).map(name => ({ label: name, value: name }));
        }
    }

    @wire(getLeadStatusNames)
    wiredLeadStatuses({ error, data }) {
        if (data) {
            this.leadStatusOptions = (data || []).map(name => ({ label: name, value: name }));
        } else if (error) {
            console.error('Error loading lead statuses:', error);
            this.leadStatusOptions = [];
        }
    }

    currentUserId = userId;
    refreshTimer = null;
    refreshInterval = 300000; // 5 minutes
    @track refreshCountdown = 300; // seconds remaining
    countdownTimer = null;

    async connectedCallback() {
        // Load the Plus Jakarta Sans font first
        await this.loadFonts();
        
        this.loadQueueItem();
        this.startAutoRefresh();
        
        // Listen for page visibility changes to detect when widget is minimized
        document.addEventListener('visibilitychange', this.handleVisibilityChange.bind(this));
        // Suppress unhandled Promise rejections that may bubble from framework internals
        try {
            this._unhandledRejectionHandler = (evt) => {
                try { console.log('Suppressed async rejection:', evt && (evt.reason || evt)); } catch (e) {}
                try { evt && evt.preventDefault && evt.preventDefault(); } catch (e2) {}
            };
            window.addEventListener('unhandledrejection', this._unhandledRejectionHandler);
        } catch (e) {}
        
        if (window.sforce && window.sforce.opencti) {
            window.sforce.opencti.enableClickToDial({
                callback: (response) => {
                    if (response.success) {
                        console.log('Click-to-dial enabled for NBA Queue Widget');
                    }
                }
            });
            window.sforce.opencti.onClickToDial({
                listener: this.handleCTIClickToDial.bind(this)
            });
        }
    }
    
    handleVisibilityChange() {
        // Track when the page becomes hidden (widget minimized) or visible (widget opened)
        this.isPageHidden = document.hidden;
        console.log('Page visibility changed:', this.isPageHidden ? 'Hidden' : 'Visible');
    }

    async loadFonts() {
        try {
            await loadStyle(this, PlusJakartaSans + '/PlusJakartaSans.css');
            this.fontLoaded = true;
            console.log('Plus Jakarta Sans font loaded successfully');
        } catch (error) {
            console.error('Error loading Plus Jakarta Sans font:', error);
            // Fallback to system fonts if loading fails
        }
    }

    handleManualRefresh() {
        console.log('Manual refresh triggered by user');
        this.showToast('Info', 'Refreshing queue...', 'info');
        // Reset countdown immediately
        this.refreshCountdown = Math.floor(this.refreshInterval / 1000);
        this.loadQueueItem().catch(error => {
            console.error('Manual refresh failed:', error);
            this.showToast('Error', 'Failed to refresh queue', 'error');
        });
    }

    // Method to trigger blinking alert for new actions
    triggerBlinkingAlert() {
        this.isBlinking = true;
        // Stop blinking after 5 seconds
        setTimeout(() => {
            this.isBlinking = false;
        }, 5000);
        
        // Try to show browser notification for utility bar context
        this.showBrowserNotification();
    }
    
    showBrowserNotification() {
        if ('Notification' in window && Notification.permission === 'granted') {
            new Notification('Next Best Action', {
                body: 'New action item available in your queue',
                icon: '/resource/slds/assets/icons/utility/notification.svg',
                tag: 'nba-queue-pending',
                requireInteraction: true, // Keep notification until user interacts
                silent: false // Play notification sound
            });
        } else if ('Notification' in window && Notification.permission !== 'denied') {
            Notification.requestPermission().then(permission => {
                if (permission === 'granted') {
                    this.showBrowserNotification();
                }
            });
        }
        
        // Flash the page title as a fallback
        this.flashPageTitle();
        
        // Also try to make a beep sound if possible
        this.playNotificationSound();
    }
    
    playNotificationSound() {
        try {
            // Create a simple beep sound using Web Audio API
            const audioContext = new (window.AudioContext || window.webkitAudioContext)();
            const oscillator = audioContext.createOscillator();
            const gainNode = audioContext.createGain();
            
            oscillator.connect(gainNode);
            gainNode.connect(audioContext.destination);
            
            oscillator.frequency.setValueAtTime(800, audioContext.currentTime);
            oscillator.type = 'sine';
            
            gainNode.gain.setValueAtTime(0.1, audioContext.currentTime);
            gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.5);
            
            oscillator.start(audioContext.currentTime);
            oscillator.stop(audioContext.currentTime + 0.5);
        } catch (error) {
            console.log('Could not play notification sound:', error);
        }
    }
    
    flashPageTitle() {
        const originalTitle = document.title;
        let flashCount = 0;
        const maxFlashes = 10;
        
        const flashInterval = setInterval(() => {
            if (flashCount >= maxFlashes) {
                document.title = originalTitle;
                clearInterval(flashInterval);
                return;
            }
            
            document.title = flashCount % 2 === 0 ? '🚨 PENDING ACTION 🚨' : originalTitle;
            flashCount++;
        }, 1000);
    }
    
    isWidgetVisible() {
        // Check if the widget element is visible in the viewport
        const widgetElement = this.template.querySelector('.nba-widget-card');
        if (!widgetElement) return false;
        
        const rect = widgetElement.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0 && 
               rect.top < window.innerHeight && 
               rect.bottom > 0;
    }



    async loadQueueItem() {
        console.log('=== NBA Queue Widget Debug ===');
        console.log('Current User ID:', this.currentUserId);
        
        // Reset contact selection mode when loading a new item
        this.isInContactSelectionMode = false;
        this.showContactConfirmationModal = false;
        
        // Update last refresh time
        this.lastRefreshTime = new Date();
        
        try {
            const result = await getNextQueueItemWithDetails({ userId: this.currentUserId });
            console.log('Queue item data received:', result);
            
            if (result && result.queueItem) {
                const oppId = result.queueItem.Opportunity__c || null;
                if (this.messageContext && oppId && oppId !== this._lastPublishedOppId) {
                    try { publish(this.messageContext, OpportunityContextChannel, { recordId: oppId }); } catch (e) {}
                    this._lastPublishedOppId = oppId;
                }
                // Always broadcast DOM event so Aura Mogli wrapper updates context
                try {
                    if (oppId) {
                        const evt = new CustomEvent('nbaopportunitychange', { detail: { recordId: oppId }, bubbles: true, composed: true });
                        window.dispatchEvent(evt);
                    }
                } catch (e) {}

                // Check if this is a new item (different from current)
                const isNewItem = !this.queueItem || this.queueItem.Id !== result.queueItem.Id;
                
                // Store priority score details
                this.originalScore = result.originalScore;
                this.adjustedScore = result.adjustedScore;
                this.webUsageMultiplier = result.webUsageMultiplier;
                this.bestTimeMultiplier = result.bestTimeMultiplier;
                this.webUsageApplied = result.webUsageApplied;
                this.bestTimeApplied = result.bestTimeApplied;
                
                console.log('Priority Score Details:', {
                    original: this.originalScore,
                    adjusted: this.adjustedScore,
                    webUsageApplied: this.webUsageApplied,
                    bestTimeApplied: this.bestTimeApplied
                });
                
            this.queueItem = {
                    ...result.queueItem,
                    formattedDueDate: this.formatDate(result.queueItem.Due_Date__c),
                    formattedCloseDate: this.formatDate(result.queueItem.Close_Date__c),
                    formattedLastCallDate: this.formatDateTime(result.queueItem.Opportunity__r?.Last_Call_Date_Time__c),
                    actionIcon: this.getActionIcon(result.queueItem.Action_Type__c),
                    isPayrollAction: this.isPayrollAction(result.queueItem.Action_Type__c),
                    featuresList: '',
                    isExpanded: false,
                    expandIcon: 'utility:chevronright',
                    expandText: 'Show'
                };
                
                // Default to Contact tab (Opportunity details tab removed)
                this.activeTab = 'contact';
                
                // Run non-critical follow-ups in parallel to cut round trips
                try {
                    const [_, upNextRes, contactData] = await Promise.all([
                        markAsViewed({ queueItemId: result.queueItem.Id }).catch((e)=>{ console.warn('markAsViewed failed', e); }),
                        getUpNextItem({ userId: this.currentUserId, excludeQueueItemId: result.queueItem.Id }).catch(() => null),
                        resolvePrimaryContactForQueueItem({ queueItemId: result.queueItem.Id }).catch(() => null)
                    ]);
                    this.upNextItem = upNextRes && upNextRes.upNext ? upNextRes.upNext : null;
                    this.opportunityPrimaryContact = contactData || null;
                } catch (e) {
                    console.warn('Parallel follow-ups failed', e);
                    this.upNextItem = null;
                    this.opportunityPrimaryContact = null;
                }

                // Pre-populate call notes with opportunity description if available
                if (result.queueItem.Opportunity__r && result.queueItem.Opportunity__r.Description) {
                    this.callNotes = result.queueItem.Opportunity__r.Description;
                } else {
                    this.callNotes = '';
                }

                // Fire event so parent pages can refresh their detail views
                try {
                    if (isNewItem) {
                        this.dispatchEvent(new CustomEvent('nbaqueuechange', { detail: { queueItemId: result.queueItem.Id } }));
                        const opp = result.queueItem.Opportunity__c || null;
                        if (opp) {
                            const evt = new CustomEvent('nbaopportunitychange', { detail: { recordId: opp }, bubbles: true, composed: true });
                            window.dispatchEvent(evt);
                        }
                        const leadId = result.queueItem.Lead__c || null;
                        if (leadId) {
                            const le = new CustomEvent('nbaleadchange', { detail: { recordId: leadId }, bubbles: true, composed: true });
                            window.dispatchEvent(le);
                        }
                    }
                } catch (e) {}
                
                console.log('Queue item processed successfully');
                
                // Only trigger blinking alert if this is a new item and widget might be minimized
                if (isNewItem) {
                    // Check if page is hidden (widget minimized) or widget is not visible
                    if (this.isPageHidden || document.hidden || !this.isWidgetVisible()) {
                        console.log('New item detected while widget appears minimized - triggering alert');
                        this.triggerBlinkingAlert();
                    } else {
                        console.log('New item detected while widget is visible - no alert needed');
                    }
                }
            } else {
                console.log('No queue items found for user');
                this.queueItem = null;
                this.upNextItem = null;
                this.originalScore = null;
                this.adjustedScore = null;
                this.webUsageMultiplier = null;
                this.bestTimeMultiplier = null;
                this.webUsageApplied = false;
                this.bestTimeApplied = false;
            }
        } catch (error) {
            console.error('Error loading queue item:', error);
            console.error('Error details:', JSON.stringify(error, null, 2));
            this.showToast('Error', 'Failed to load queue item', 'error');
            this.queueItem = null;
            this.upNextItem = null;
        }
    }

    isPayrollAction(actionType) {
        return actionType === 'Payroll Opportunity Call' || actionType === 'Payroll Prospecting Call';
    }

    formatFeatureUsage(features) {
        if (!features) return '';
        return features.split(';').join(', ');
    }

    formatDateTime(dateTimeValue) {
        if (!dateTimeValue) return '';
        const date = new Date(dateTimeValue);
        return date.toLocaleString();
    }



    disconnectedCallback() {
        this.stopAutoRefresh();
        try {
            if (this._unhandledRejectionHandler) {
                window.removeEventListener('unhandledrejection', this._unhandledRejectionHandler);
                this._unhandledRejectionHandler = null;
            }
        } catch (e) {}
    }

    startAutoRefresh() {
        console.log('Starting auto-refresh countdown - refresh every 30 seconds');
        this.refreshCountdown = Math.floor(this.refreshInterval / 1000);
        if (this.countdownTimer) {
            clearInterval(this.countdownTimer);
        }
        this.countdownTimer = setInterval(() => {
            if (this.refreshCountdown > 0) {
                this.refreshCountdown -= 1;
            }
            if (this.refreshCountdown === 0) {
                if (!this.isLoading && !this.showCallDispositionModal) {
                    console.log('Auto-refresh (countdown reached 0) - loading queue');
                    this.loadQueueItem().catch(error => {
                        console.error('Auto-refresh failed: ', error);
                    });
                } else {
                    console.log('Auto-refresh skipped - component is loading or modal is open');
                }
                // reset countdown regardless
                this.refreshCountdown = Math.floor(this.refreshInterval / 1000);
            }
        }, 1000);
    }

    stopAutoRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = null;
        }
        if (this.countdownTimer) {
            clearInterval(this.countdownTimer);
            this.countdownTimer = null;
        }
    }

    get hasItems() {
        return this.queueItem && this.queueItem.Id;
    }

    get containerStyle() {
        return `--panel-height: ${this.panelHeight}px;`;
    }

    get widgetClass() {
        let classes = 'nba-widget-card';
        if (this.showCallDispositionForm || this.showDismissForm) {
            classes += ' nba-widget-form-active';
        }
        if (this.isBlinking) {
            classes += ' nba-widget-blinking';
        }
        // Add pulsing class when there's a pending action
        if (this.pendingAction) {
            classes += ' nba-widget-pending-pulse';
        }
        return classes;
    }

    get hasPendingAction() {
        return this.pendingAction !== null;
    }

    get pendingActionText() {
        if (this.pendingAction === 'call') {
            return 'Call Disposition Required';
        } else if (this.pendingAction === 'dismiss') {
            return 'Dismiss Reason Required';
        }
        return '';
    }



    get callDispositionOptions() {
        return [
            { label: 'Connected - DM', value: 'Connected - DM' },
            { label: 'Connected - GK', value: 'Connected - GK' },
            { label: 'Attempted - Left Voicemail', value: 'Attempted - Left Voicemail' },
            { label: 'Attempted - No Voicemail', value: 'Attempted - No Voicemail' },
            { label: 'Invalid Number', value: 'Invalid Number' },
            { label: 'Not Interested', value: 'Not Interested' }
        ];
    }

    get showNextStepsFields() {
		const closedStages = [
			'Closed Won - Pending Implementation',
			'Closed Won',
			'Closed Lost'
		];
        if (this.queueItem?.Lead__c) {
            return this.callDisposition === 'Connected - DM';
        }
		return this.callDisposition === 'Connected - DM';
    }


    get hasOpportunity() {
        return !!(this.queueItem && this.queueItem.Opportunity__c);
    }
    get hasLead() {
        return !!(this.queueItem && this.queueItem.Lead__c);
    }

    handleAcceptAction(event) {
        const itemId = event.currentTarget?.dataset?.id || (event.target && event.target.dataset && event.target.dataset.id);
        if (itemId && (!this.queueItem || this.queueItem.Id !== itemId)) {
            // If the queueItem is not the one being acted on, fetch it (future-proofing for lists)
            // For now, just use the current queueItem
        }
        this.selectedItem = this.queueItem;
        
        // Handle different action types
        const actionType = this.queueItem?.Action_Type__c || '';
        if (actionType === 'Event') {
            this.handleEventAccept();
        } else if (actionType === 'Email') {
            this.handleEmailAccept();
        } else if (actionType.toLowerCase().includes('call')) {
            // Experimental: Two-stage accept process for calls only
            // Stage 1: Call acceptAction to set status to In Progress, then show contact confirmation
            this.executeAcceptActionForCall();
        } else {
            this.executeAcceptAction();
        }
    }

    handleDismissAction(event) {
        console.log('Dismiss action triggered');
        // Ensure buttons are enabled when opening the form
        this.isLoading = false;
        this.showDismissForm = true;
        this.dismissReason = '';
        this.pendingAction = 'dismiss';
        console.log('showDismissForm set to:', this.showDismissForm);
    }
    closeDismissForm() {
        console.log('Closing dismiss form');
        this.showDismissForm = false;
        this.dismissReason = '';
        this.pendingAction = null;
    }
    handleDismissReasonChange(event) {
        this.dismissReason = event.target.value;
    }
    handleDismissalCategoryChange = (event) => { this.dismissalCategory = event.target.value; }
    handleSnoozeScheduledAtChange = (event) => { this.snoozeScheduledAt = event.target.value; }
    // Removed dynamic snooze hours handler; fixed to 3 hours
    submitDismissReason() {
        const category = this.dismissalCategory;
        if (category === 'Call Scheduled') {
            if (!this.snoozeScheduledAt) {
                this.showToast('Error', 'Please select the scheduled call date/time', 'error');
                return;
            }
            this.isLoading = true;
            snoozeQueueItem({ queueItemId: this.queueItem.Id, category, scheduledDateTime: new Date(this.snoozeScheduledAt), snoozeHours: null })
                .then(() => {
                    this.showToast('Success', 'Action snoozed until 15 minutes before the scheduled call', 'success');
                    this.showDismissForm = false;
                    return this.loadQueueItem();
                })
                .finally(() => { this.isLoading = false; });
            return;
        }
        if (category === 'Time Zone') {
            const hours = 3; // fixed 3-hour snooze
            this.isLoading = true;
            snoozeQueueItem({ queueItemId: this.queueItem.Id, category, scheduledDateTime: null, snoozeHours: hours })
                .then(() => {
                    this.showToast('Success', `Action snoozed for ${hours} hours due to time zone`, 'success');
                    this.showDismissForm = false;
                    return this.loadQueueItem();
                })
                .finally(() => { this.isLoading = false; });
            return;
        }
        // Other: fall back to standard dismissal with text reason
        if (!this.dismissReason || this.dismissReason.trim() === '') {
            this.showToast('Error', 'Please enter a reason for dismissal', 'error');
            return;
        }
        this.selectedItem = this.queueItem;
        this.executeDismissActionWithReason();
        this.showDismissForm = false;
    }
    executeDismissActionWithReason() {
        this.isLoading = true;
        dismissAction({ queueItemId: this.selectedItem.Id, dismissalReason: this.dismissReason })
            .then(() => {
                this.showToast('Success', 'Action dismissed', 'success');
                // Clear the current queue item immediately
                this.queueItem = null;
                // Then refresh to get the next item or confirm no more items
                return this.loadQueueItem();
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Failed to dismiss action', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    executeAcceptAction() {
        console.log('executeAcceptAction started');
        this.isLoading = true;
        // Watchdog: clear loading if backend call hangs unexpectedly
        try { if (this._acceptWatchdog) clearTimeout(this._acceptWatchdog); } catch (e) {}
        this._acceptWatchdog = setTimeout(() => {
            if (this.isLoading) {
                this.isLoading = false;
                this.showToast('Warning', 'Accept action is taking longer than expected. Please retry.', 'warning');
            }
        }, 8000);

        const actionType = this.selectedItem.Action_Type__c;
        const currentItem = this.selectedItem;
        const isCall = (actionType || '').toLowerCase().includes('call');
        
        console.log('executeAcceptAction - currentItem Best_Number_to_Call__c:', currentItem?.Best_Number_to_Call__c);
        console.log('executeAcceptAction - queueItem Best_Number_to_Call__c:', this.queueItem?.Best_Number_to_Call__c);
        console.log('executeAcceptAction - currentItem Person_Called__c:', currentItem?.Person_Called__c);
        console.log('executeAcceptAction - queueItem Person_Called__c:', this.queueItem?.Person_Called__c);

        console.log('Calling Apex acceptAction with', { id: this.selectedItem?.Id, isCall });
        acceptAction({ queueItemId: this.selectedItem.Id, additionalNotes: '' })
            .then((taskId) => {
                console.log('Accept action successful, task ID:', taskId);
                this.showToast('Success', 'Action accepted', 'success');
                try { this.dispatchEvent(new CustomEvent('nbaqueuechange', { detail: { queueItemId: this.selectedItem.Id } })); } catch (e) {}
                // Task will be created when call disposition is saved
                if (isCall) {
                    // Unified call behavior for Opp and Lead
                    try {
                        const maybePromise = this.launchAction(currentItem);
                        if (maybePromise && typeof maybePromise.then === 'function') {
                            maybePromise.catch(err => { console.log('launchAction error (call):', err); });
                        }
                    } catch (e) { console.log('launchAction threw (sync):', e); }
                    // Open disposition form after a brief delay so Talkdesk DOM click executes first
                    setTimeout(() => { this.showCallDispositionForm = true; }, 700);
                    this.pendingAction = 'call';
                } else {
                    try {
                        const maybePromise = this.launchAction(currentItem);
                        if (maybePromise && typeof maybePromise.then === 'function') {
                            maybePromise.catch(err => { console.log('launchAction error (non-call):', err); });
                        }
                    } catch (e) { console.log('launchAction threw (sync non-call):', e); }
                    return this.loadQueueItem();
                }
            })
            .catch(error => {
                console.error('Accept action error:', JSON.stringify(error));
                let message = error?.body?.message || 'Failed to accept action';
                this.showToast('Error', message, 'error');
            })
            .finally(() => {
                try { if (this._acceptWatchdog) clearTimeout(this._acceptWatchdog); } catch (e) {}
                this.isLoading = false;
            });
    }

    // Experimental: Execute accept action for call, then show contact confirmation
    async executeAcceptActionForCall() {
        console.log('executeAcceptActionForCall started');
        
        // First, call acceptAction to set status to In Progress
        try {
            await acceptAction({ queueItemId: this.selectedItem.Id, additionalNotes: '' });
            console.log('Accept action successful for call');
            
            // Then navigate to record and show contact confirmation
            this.navigateToRecordAndShowConfirmation();
        } catch (error) {
            console.error('Error in acceptAction for call:', error);
            this.showToast('Error', 'Failed to accept action: ' + error.body?.message, 'error');
        }
    }

    // Experimental: Navigate to record and show contact confirmation
    navigateToRecordAndShowConfirmation() {
        console.log('navigateToRecordAndShowConfirmation started');
        
        // Navigate to the appropriate record
        if (this.queueItem?.Lead__c) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.queueItem.Lead__c,
                    objectApiName: 'Lead',
                    actionName: 'view'
                }
            });
        } else if (this.queueItem?.Opportunity__c) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.queueItem.Opportunity__c,
                    objectApiName: 'Opportunity',
                    actionName: 'view'
                }
            });
        } else if (this.queueItem?.Account__c) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.queueItem.Account__c,
                    objectApiName: 'Account',
                    actionName: 'view'
                }
            });
        }
        
        // Load available contacts and phone numbers
        this.loadContactOptions();
        
        // Set contact selection mode and show the modal
        this.isInContactSelectionMode = true;
        this.showContactConfirmationModal = true;
    }
    
    // Load available contacts and phone numbers for the record
    async loadContactOptions() {
        // Use the same call logic as the original widget
        let defaultContactId = '';
        let defaultContactName = '';
        let defaultPhoneNumber = '';
        
        // PRIORITY: Always use Best Person to Call and Best Number to Call from NBA Queue if available
        if (this.queueItem?.Best_Person_to_Call__c && this.queueItem?.Best_Number_to_Call__c) {
            defaultContactId = this.queueItem.Best_Person_to_Call__c;
            defaultContactName = this.queueItem.Best_Person_to_Call__r?.Name || '';
            defaultPhoneNumber = this.queueItem.Best_Number_to_Call__c;
        } else {
            // Fallback to existing logic if Best Person/Number not set
            if (this.queueItem?.Opportunity__c) {
                // For Opportunity calls, use the opportunity primary contact logic
                if (this.queueItem?.Best_Person_to_Call__c) {
                    defaultContactId = this.queueItem.Best_Person_to_Call__c;
                    defaultContactName = this.queueItem.Best_Person_to_Call__r?.Name || '';
                    defaultPhoneNumber = this.queueItem.Best_Number_to_Call__c || '';
                } else if (this.opportunityPrimaryContact?.contactId) {
                    defaultContactId = this.opportunityPrimaryContact.contactId;
                    defaultContactName = this.opportunityPrimaryContact.contactName;
                    defaultPhoneNumber = this.opportunityPrimaryContact.contactPhone;
                }
            } else if (this.queueItem?.Account__c) {
                // For Account calls, use account primary contact
                if (this.queueItem?.Best_Person_to_Call__c) {
                    defaultContactId = this.queueItem.Best_Person_to_Call__c;
                    defaultContactName = this.queueItem.Best_Person_to_Call__r?.Name || '';
                    defaultPhoneNumber = this.queueItem.Best_Number_to_Call__c || '';
                }
            } else if (this.queueItem?.Lead__c) {
                // For Lead calls, use lead contact info
                defaultContactId = this.queueItem.Lead__c;
                defaultContactName = this.queueItem.Lead__r?.Name || '';
                defaultPhoneNumber = this.queueItem.Best_Number_to_Call__c || this.queueItem.Lead__r?.Phone || '';
            }
        }
        
        // Set default values
        this.selectedContactId = defaultContactId;
        this.selectedContactName = defaultContactName;
        this.selectedPhoneNumber = defaultPhoneNumber;
        
        // Build available contacts
        this.availableContacts = [];
        
        // Add the default contact
        if (defaultContactId && defaultContactName) {
            this.availableContacts.push({
                id: defaultContactId,
                name: defaultContactName,
                phone: this.queueItem?.Best_Person_to_Call__r?.Phone || '',
                mobilePhone: this.queueItem?.Best_Person_to_Call__r?.MobilePhone || '',
                otherPhone: this.queueItem?.Best_Person_to_Call__r?.OtherPhone || ''
            });
        }
        
            // Add opportunity primary contact if different
            if (this.opportunityPrimaryContact?.contactId && 
                this.opportunityPrimaryContact.contactId !== defaultContactId) {
                this.availableContacts.push({
                    id: this.opportunityPrimaryContact.contactId,
                    name: this.opportunityPrimaryContact.contactName,
                    phone: this.opportunityPrimaryContact.contactPhone,
                    mobilePhone: '',
                    otherPhone: ''
                });
            }
        
        // Fetch and add all account contacts if we have an account
        if (this.queueItem?.Account__c) {
            try {
                const accountContacts = await getAccountContacts({ accountId: this.queueItem.Account__c });
                
                for (const contact of accountContacts) {
                    // Only add if not already in the list
                    const existingContact = this.availableContacts.find(c => c.id === contact.id);
                    if (!existingContact) {
                        this.availableContacts.push({
                            id: contact.id,
                            name: contact.name,
                            phone: contact.phone || '',
                            mobilePhone: contact.mobilePhone || '',
                            otherPhone: contact.otherPhone || '',
                            title: contact.title || '',
                            department: contact.department || ''
                        });
                    }
                }
            } catch (error) {
                console.error('Error fetching account contacts:', error);
            }
        }
        
        // Add "Other" option for manual phone input (always at the bottom)
        this.availableContacts.push({
            id: 'other',
            name: 'Other (Manual Entry)',
            phone: '',
            mobilePhone: '',
            otherPhone: ''
        });
        
        // Update phone options for the selected contact
        this.updatePhoneOptionsForContact();
        
        // Set default phone display
        this.updatePhoneDisplay();
    }
    
    // Handle contact selection change
    handleContactChange(event) {
        this.selectedContactId = event.target.value;
        // Update contact name and phone options
        const selectedContact = this.availableContacts.find(contact => contact.id === this.selectedContactId);
        if (selectedContact) {
            this.selectedContactName = selectedContact.name;
        }
        
        // Check if "Other" option is selected
        if (this.selectedContactId === 'other') {
            this.showManualPhoneInput = true;
            this.availablePhoneNumbers = []; // Clear phone options
            this.selectedPhoneNumber = this.manualPhoneNumber || '';
        } else {
            this.showManualPhoneInput = false;
            this.manualPhoneNumber = '';
            this.updatePhoneOptionsForContact();
        }
        
        this.updatePhoneDisplay();
    }
    
    // Handle phone number selection change
    handlePhoneChange(event) {
        this.selectedPhoneNumber = event.target.value;
        this.updatePhoneDisplay();
    }
    
    // Handle manual phone number input
    handleManualPhoneChange(event) {
        this.manualPhoneNumber = event.target.value;
        this.selectedPhoneNumber = event.target.value;
        this.updatePhoneDisplay();
    }
    
    // Update phone display text
    updatePhoneDisplay() {
        if (this.selectedPhoneNumber) {
            if (this.showManualPhoneInput) {
                // For manual entry, just show the number
                this.selectedPhoneDisplay = this.selectedPhoneNumber;
            } else {
                // For dropdown selection, show the formatted label
                const phoneOption = this.availablePhoneNumbers.find(option => option.value === this.selectedPhoneNumber);
                this.selectedPhoneDisplay = phoneOption ? phoneOption.label : this.selectedPhoneNumber;
            }
        } else {
            this.selectedPhoneDisplay = '';
        }
    }
    
    // Update phone options based on selected contact
    updatePhoneOptionsForContact() {
        const selectedContact = this.availableContacts.find(contact => contact.id === this.selectedContactId);
        if (selectedContact) {
            this.availablePhoneNumbers = [];
            
            // Add selected contact's phone numbers only (Phone is always first if available)
            if (selectedContact.phone) {
                this.availablePhoneNumbers.push({
                    value: selectedContact.phone,
                    label: selectedContact.phone + ' (Phone)'
                });
            }
            if (selectedContact.mobilePhone) {
                this.availablePhoneNumbers.push({
                    value: selectedContact.mobilePhone,
                    label: selectedContact.mobilePhone + ' (Mobile)'
                });
            }
            if (selectedContact.otherPhone) {
                this.availablePhoneNumbers.push({
                    value: selectedContact.otherPhone,
                    label: selectedContact.otherPhone + ' (Other Phone)'
                });
            }
            
            // Add account and lead phone numbers if available (as fallback options)
            if (this.queueItem?.Account__r?.Phone && !this.availablePhoneNumbers.find(p => p.value === this.queueItem.Account__r.Phone)) {
                this.availablePhoneNumbers.push({
                    value: this.queueItem.Account__r.Phone,
                    label: this.queueItem.Account__r.Phone + ' (Account Phone)'
                });
            }
            if (this.queueItem?.Lead__r?.Phone && !this.availablePhoneNumbers.find(p => p.value === this.queueItem.Lead__r.Phone)) {
                this.availablePhoneNumbers.push({
                    value: this.queueItem.Lead__r.Phone,
                    label: this.queueItem.Lead__r.Phone + ' (Lead Phone)'
                });
            }
            if (this.queueItem?.Lead__r?.MobilePhone && !this.availablePhoneNumbers.find(p => p.value === this.queueItem.Lead__r.MobilePhone)) {
                this.availablePhoneNumbers.push({
                    value: this.queueItem.Lead__r.MobilePhone,
                    label: this.queueItem.Lead__r.MobilePhone + ' (Lead Mobile)'
                });
            }
            
            // Reset selected phone number to the first available option
            this.selectedPhoneNumber = this.availablePhoneNumbers[0]?.value || '';
        }
    }
    
    // Handle "Call Now" button click
    async handleCallNow() {
        console.log('Call Now clicked with contact:', this.selectedContactId, 'phone:', this.selectedPhoneNumber);
        
        // Close the contact confirmation modal and exit contact selection mode
        this.showContactConfirmationModal = false;
        this.isInContactSelectionMode = false;
        
        // Update the queue item with selected contact and phone
        this.updateQueueItemWithSelectedContact();
        
        // Update the database record with the selected values BEFORE calling accept
        try {
            await this.updateQueueItemInDatabase();
            console.log('Database record updated successfully');
        } catch (error) {
            console.error('Error updating database record:', error);
            this.showToast('Error', 'Failed to update contact information', 'error');
            return;
        }
        
        // Proceed with the normal accept action
        this.executeAcceptAction();
    }
    
    // Handle redial action - show contact selection modal
    handleRedial() {
        // Close the call disposition form
        this.showCallDispositionForm = false;
        
        // Show the contact confirmation modal again for contact/number selection
        this.showContactConfirmationModal = true;
        
        // Reset the selected values to current defaults
        this.selectedContactId = this.queueItem?.Best_Person_to_Call__c || '';
        this.selectedPhoneNumber = this.queueItem?.Best_Number_to_Call__c || '';
        this.selectedContactName = this.queueItem?.Best_Person_to_Call__r?.Name || '';
        this.selectedPhoneDisplay = this.queueItem?.Best_Number_to_Call__c || '';
        this.showManualPhoneInput = false;
        this.manualPhoneNumber = '';
    }
    
    // Redial the specified phone number
    redialNumber(phoneNumber) {
        if (!phoneNumber) return;
        
        console.log('Redialing number:', phoneNumber);
        
        // Clean and format the number
        let cleanedNumber = phoneNumber.replace(/\D/g, '');
        if (!phoneNumber.startsWith('+')) {
            if (cleanedNumber.length === 10) {
                cleanedNumber = '1' + cleanedNumber;
            }
            cleanedNumber = '+' + cleanedNumber;
        }
        
        // Store the current phone number for display
        this.currentPhoneNumber = cleanedNumber;
        
        // Trigger the click-to-call
        this.triggerClickToCall(cleanedNumber);
        this.showToast('Redialing', `Calling ${cleanedNumber}`, 'info');
    }
    
    // Trigger click-to-call via tel: link
    triggerClickToCall(phoneNumber) {
        if (!phoneNumber) return;
        
        // Create a temporary anchor element with tel: link
        const a = document.createElement('a');
        a.href = `tel:${phoneNumber}`;
        a.style.display = 'none';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    }
    
    // Update queue item with selected contact and phone
    updateQueueItemWithSelectedContact() {
        console.log('=== updateQueueItemWithSelectedContact Debug ===');
        console.log('selectedContactId:', this.selectedContactId);
        console.log('selectedContactName:', this.selectedContactName);
        console.log('selectedPhoneNumber:', this.selectedPhoneNumber);
        console.log('showManualPhoneInput:', this.showManualPhoneInput);
        
        // Update selectedItem with the chosen contact and phone for display purposes
        if (this.selectedItem) {
            this.selectedItem.Best_Person_to_Call__c = this.selectedContactId;
            this.selectedItem.Best_Number_to_Call__c = this.selectedPhoneNumber;
        }
        
        // Update the main queueItem for call logic but don't overwrite the original Best fields
        if (this.queueItem) {
            // Keep the original Best_Person_to_Call__c and Best_Number_to_Call__c unchanged
            // Only update the tracking fields
            
            // Update the related contact info if we have it
            if (this.selectedContactId && this.availableContacts.length > 0) {
                const selectedContact = this.availableContacts.find(contact => contact.id === this.selectedContactId);
                if (selectedContact) {
                    // Update the Best_Person_to_Call__r relationship data
                    this.queueItem.Best_Person_to_Call__r = {
                        Name: selectedContact.name,
                        Phone: selectedContact.phone,
                        MobilePhone: selectedContact.mobilePhone
                    };
                }
            }
            
            // Set Person_Called__c field for tracking
            if (this.selectedContactId === 'other') {
                this.queueItem.Person_Called__c = 'Other Manual Entry';
                console.log('Set Person_Called__c to: Other Manual Entry');
            } else if (this.selectedContactName) {
                this.queueItem.Person_Called__c = this.selectedContactName;
                console.log('Set Person_Called__c to:', this.selectedContactName);
            } else {
                console.log('No Person_Called__c set - selectedContactName is empty');
            }
        }
        
        console.log('Updated queueItem with selected contact:', this.selectedContactId, 'and phone:', this.selectedPhoneNumber);
        console.log('Person_Called__c set to:', this.queueItem?.Person_Called__c);
        console.log('Best_Number_to_Call__c set to:', this.queueItem?.Best_Number_to_Call__c);
    }
    
    // Update the database record with selected contact and phone information
    async updateQueueItemInDatabase() {
        if (!this.queueItem?.Id) {
            throw new Error('No queue item ID available');
        }
        
        console.log('Updating database record for queue item:', this.queueItem.Id);
        console.log('Person_Called__c:', this.queueItem.Person_Called__c);
        console.log('Number_Dialed__c:', this.selectedPhoneNumber);
        
        try {
            await updateQueueItem({
                queueItemId: this.queueItem.Id,
                bestPersonToCall: null, // Don't update the original Best fields
                bestNumberToCall: null, // Don't update the original Best fields
                personCalled: this.queueItem.Person_Called__c,
                numberDialed: this.selectedPhoneNumber
            });
        } catch (error) {
            console.error('Error updating queue item in database:', error);
            throw error;
        }
    }
    
    // Handle canceling the contact confirmation
    async handleCancelContactConfirmation() {
        // Close the modal and reset selections
        this.showContactConfirmationModal = false;
        this.selectedContactId = '';
        this.selectedPhoneNumber = '';
        this.isInContactSelectionMode = false;
        
        // Revert the status back to Pending
        if (this.selectedItem && this.selectedItem.Id) {
            try {
                await cancelCallDisposition({ queueItemId: this.selectedItem.Id });
                console.log('Status reverted to Pending after cancel');
                // Refresh the queue item to reflect the status change
                await this.loadQueueItem();
            } catch (error) {
                console.error('Error reverting status to Pending:', error);
                this.showToast('Error', 'Failed to revert status: ' + error.body?.message, 'error');
            }
        }
    }

    closeCallDispositionForm() {
        // Cancel the call disposition and revert status to "Pending"
        if (this.selectedItem && this.selectedItem.Id) {
            cancelCallDisposition({ queueItemId: this.selectedItem.Id })
                .then(() => {
                    console.log('Call disposition cancelled, status reverted to Pending');
                })
                .catch(error => {
                    console.error('Error cancelling call disposition:', error);
                });
        }
        
        this.showCallDispositionForm = false;
        this.currentTaskId = null;
        this.callDisposition = '';
        // Don't clear callNotes here - let loadQueueItem handle it
        this.pendingAction = null;
        // Load next queue item when closing the form
        this.loadQueueItem();
    }

    handleAccountClick(event) {
        const accountId = event.target.dataset.accountId;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    getAccountTitle(item) {
        return item && item.Account__r && item.Account__r.Name
            ? `Navigate to ${item.Account__r.Name}`
            : '';
    }



    handleCallDispositionChange(event) {
        this.callDisposition = event.target.value;
    }

    handleCallNotesChange(event) {
        this.callNotes = event.target.value;
    }

    handleNextStepDateChange = (event) => { this.nextStepDate = event.target.value; }
    handleNextStepsChange = (event) => { this.nextSteps = event.target.value; }
    handleFutureDateChange = (event) => { this.futureFollowUpDate = event.target.value; }
    handleFutureReasonChange = (event) => { this.futureFollowUpReason = event.target.value; }
    handleLeadStatusChange = (event) => { this.selectedLeadStatus = event.target.value; }

    handleCallDispositionSave() {
        // Basic client-side guards and debug
        if (!this.callDisposition) {
            this.showToast('Error', 'Please select a call disposition', 'error');
            return;
        }
        // Task will be created when disposition is saved
        if (!this.selectedItem || !this.selectedItem.Id) {
            console.error('CallDispositionSave: Missing selectedItem or Id');
            this.showToast('Error', 'Missing queue item context. Refresh and try again.', 'error');
            return;
        }

        // Require Next Step Date and Next Steps when disposition is Connected - DM and stage is not closed
        if (this.showNextStepsFields) {
            if (!this.nextStepDate) {
                this.showToast('Error', 'Next Step Date is required for Connected - DM', 'error');
                return;
            }
            if (!this.nextSteps || !this.nextSteps.trim()) {
                this.showToast('Error', 'Next Steps are required for Connected - DM', 'error');
                return;
            }
        }

        this.isLoading = true;
        console.log('Saving call disposition payload', {
            queueItemId: this.selectedItem?.Id,
            disposition: this.callDisposition,
            notesLen: (this.callNotes || '').length,
        });

        // Decide if a flow must run (Closed Lost or Closed Won - Pending Implementation)
        const flowRequired = false; // No stage updates, so no flow required

        const savePromise = flowRequired
            ? updateCallDispositionWithQueueIdOptions({
                  queueItemId: this.selectedItem.Id,
                  disposition: this.callDisposition,
                  callNotes: this.callNotes,
                  finalize: false
              })
            : updateCallDisposition({
                  queueItemId: this.selectedItem.Id,
                  disposition: this.callDisposition,
                  callNotes: this.callNotes
              });

        savePromise
            .then(async () => {
                // Save next steps if provided
                try {
                    if (this.showNextStepsFields) {
                        if (this.queueItem?.Lead__c) {
                            await saveNextStepsWithLead({
                                queueItemId: this.selectedItem.Id,
                                nextStepDate: this.nextStepDate || null,
                                nextSteps: this.nextSteps || null,
                                newOpportunityStage: null,
                                newLeadStatus: this.selectedLeadStatus || null
                            });
                        } else if (this.hasOpportunity) {
                            await saveNextSteps({
                                queueItemId: this.selectedItem.Id,
                                nextStepDate: this.nextStepDate || null,
                                nextSteps: this.nextSteps || null,
                                newOpportunityStage: null
                            });
                        }
                    } else if (this.queueItem?.Lead__c && (this.selectedLeadStatus || '').length) {
                        // Allow Lead Status update without next steps
                        await saveNextStepsWithLead({
                            queueItemId: this.selectedItem.Id,
                            nextStepDate: null,
                            nextSteps: null,
                            newOpportunityStage: null,
                            newLeadStatus: this.selectedLeadStatus || null
                        });
                    }
                } catch (e) {
                    console.error('Error saving next steps/stage/lead status:', e);
                }
                this.showToast('Success', 'Call disposition saved', 'success');
                // If stage triggers flow, navigate to the Flow and skip immediate refresh
                try {
                    if (flowRequired) {
                        this.closeCallDispositionFormSuccess();
                        const oppId = this.selectedItem.Opportunity__c;
                        if (isClosedWonPending2) {
                            this.showToast('Info', 'Launching Project Initiation flow...', 'info');
                            this.openEmbeddedFlow(this.FLOW_API_PROJECT_INITIATION, oppId, this.selectedItem.Id);
                        } else if (isClosedLost2) {
                            this.showToast('Info', 'Launching Closed Lost flow...', 'info');
                            this.openEmbeddedFlow(this.FLOW_API_CLOSED_LOST, oppId, this.selectedItem.Id);
                        }
                        return; // do not refresh now to avoid closing the flow
                    }
                } catch (e) {}
                this.closeCallDispositionFormSuccess();
                // Load next queue item after saving disposition
                return this.loadQueueItem();
            })
            .catch(error => {
                let message = 'Failed to save call disposition';
                try {
                    if (error && error.body && (error.body.message || error.body.pageErrors)) {
                        message = error.body.message || (error.body.pageErrors && error.body.pageErrors[0] && error.body.pageErrors[0].message) || message;
                    }
                } catch (e) {}
                console.error('CallDispositionSave error:', JSON.stringify(error));
                this.showToast('Error', message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    closeCallDispositionFormSuccess() {
        // Close form without cancelling - status should remain "Accepted"
        this.showCallDispositionForm = false;
        this.currentTaskId = null;
        this.callDisposition = '';
        this.callNotes = '';
        this.pendingAction = null;
    }



    getActionIcon(actionType) {
        const iconMap = {
            'Call': 'utility:call',
            'Email': 'utility:email',
            'Event': 'utility:event',
            'Meeting': 'utility:event',
            'Follow_Up': 'utility:follow_up',
            'Demo': 'utility:screen_share',
            'Proposal': 'utility:contract',
            'Payroll Opportunity Call': 'utility:moneybag',
            'Payroll Prospecting Call': 'utility:currency'
        };
        return iconMap[actionType] || 'utility:task';
    }

    getActionEmoji(actionType) {
        const emojiMap = {
            'Call': '📞',
            'Email': '✉️',
            'Event': '📅',
            'Meeting': '📅',
            'Follow_Up': '📋',
            'Demo': '🖥️',
            'Proposal': '📄',
            'Payroll Opportunity Call': '💰',
            'Payroll Prospecting Call': '💵'
        };
        return emojiMap[actionType] || '📝';
    }

    formatDate(dateValue) {
        if (!dateValue) return '';
        const date = new Date(dateValue);
        return date.toLocaleDateString();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    async launchAction(queueItem) {
        try {
            const actionType = queueItem?.Action_Type__c || '';
            const accountId = queueItem?.Account__c || null;
            const accountName = queueItem?.Account__r?.Name || '';
            const opportunityId = queueItem?.Opportunity__c || null;

            switch(actionType) {
                case 'Call':
                case 'Payroll Opportunity Call':
                case 'Payroll Prospecting Call': {
                    let phoneNumber = null;
                    try {
                        phoneNumber = await this.getContactPhoneForCall(queueItem);
                    } catch (err) {
                        console.log('getContactPhoneForCall error:', err);
                        phoneNumber = this.displayContactPhone || queueItem?.Lead__r?.Phone || queueItem?.Lead__r?.MobilePhone || null;
                    }
                    try {
                        this.launchCall(accountId, accountName, phoneNumber, opportunityId);
                    } catch (e) {
                        console.log('launchCall error:', e);
                    }
                    break;
                }
                case 'Email':
                    this.launchEmail(accountId, accountName, opportunityId);
                    break;
                case 'Meeting':
                    this.launchMeeting(accountId, accountName, opportunityId);
                    break;
                case 'Demo':
                    this.launchDemo(accountId, accountName, opportunityId);
                    break;
                case 'Proposal':
                    this.launchProposal(accountId, accountName, opportunityId);
                    break;
                case 'Follow_Up':
                    this.launchFollowUp(accountId, accountName, opportunityId);
                    break;
                default:
                    if (this.navigateOnAccept) {
                        this.navigateToRecord(opportunityId || accountId);
                    }
                    break;
            }
        } catch (outer) {
            console.log('launchAction outer error:', outer);
            // never reject
        }
    }

    // Add this function to trigger click-to-call via tel: link
    triggerClickToCall(phoneNumber) {
        if (!phoneNumber) return;
        // Clean and format the number
        let cleanedNumber = phoneNumber.replace(/\D/g, '');
        if (!phoneNumber.startsWith('+')) {
            if (cleanedNumber.length === 10) {
                cleanedNumber = '1' + cleanedNumber;
            }
            cleanedNumber = '+' + cleanedNumber;
        } else {
            cleanedNumber = phoneNumber;
        }
        // Create and click a hidden anchor
        const a = document.createElement('a');
        a.href = `tel:${cleanedNumber}`;
        a.style.display = 'none';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        // Optionally, show a toast
        this.showToast('Call Initiated', `Calling ${cleanedNumber}`, 'info');
    }

    launchCall(accountId, accountName, phoneNumber, opportunityId) {
        console.log('launchCall started - Simple approach');

        const callWithNumber = (number) => {
            if (number) {
                let cleanedNumber = number.replace(/\D/g, '');
                if (!number.startsWith('+')) {
                    if (cleanedNumber.length === 10) {
                        cleanedNumber = '1' + cleanedNumber;
                    }
                    cleanedNumber = '+' + cleanedNumber;
                } else {
                    cleanedNumber = number;
                }

                const contextRecordId = opportunityId || (this.queueItem?.Lead__c || null) || accountId;
                const contextRecordName = this.queueItem?.Opportunity__r?.Name || this.queueItem?.Lead__r?.Name || accountName;
                console.log('Dialing number resolved:', cleanedNumber, 'contextId:', contextRecordId, 'contextName:', contextRecordName);

                try {
                    this.tryTalkdeskLaunch(cleanedNumber, contextRecordId, contextRecordName);
                } catch (e) { console.log('tryTalkdeskLaunch error:', e); }

                this.currentPhoneNumber = cleanedNumber;

                this.triggerClickToCall(cleanedNumber);
                this.showToast('Phone Number', `${cleanedNumber}`, 'info');

                if (this.navigateOnAccept && (opportunityId || accountId)) {
                    setTimeout(() => {
                        this.showToast('Navigation', `Navigating to ${contextRecordName} for click-to-call`, 'info');
                        this.navigateToRecord(contextRecordId);
                    }, 2000);
                }
            } else {
                console.log('No phone number available');
                this.currentPhoneNumber = 'No phone number available';
                this.showToast('No Phone Number', `No phone number found for ${accountName}`, 'warning');
                if (this.navigateOnAccept && (opportunityId || accountId)) {
                    this.navigateToRecord(opportunityId || accountId);
                }
            }
        };
        if (phoneNumber) {
            callWithNumber(phoneNumber);
        } else {
            console.log('No phone number available from getContactPhoneForCall');
            this.currentPhoneNumber = 'No phone number available';
            this.showToast('No Phone Number', `No phone number found for ${accountName}`, 'warning');
            if (this.navigateOnAccept) {
                this.navigateToRecord(opportunityId || accountId);
            }
        }
    }

    handleCTIClickToDial(response) {
        console.log('CTI Click-to-dial event:', response);
        if (response.success && response.number) {
            this.trackCallInitiation(response.number, response.recordId);
        }
    }

    trackCallInitiation(phoneNumber, recordId) {
        console.log(`Call initiated to ${phoneNumber} for record ${recordId}`);
    }

    async getAccountPhone(accountId) {
        try {
            const phoneNumber = await getAccountPhoneNumber({ accountId: accountId });
            return phoneNumber;
        } catch (error) {
            console.error('Error fetching phone:', error);
            return null;
        }
    }

    launchEmail(accountId, accountName, opportunityId) {
        // Do not open native modal; middle panel composer is used instead
        console.log('Email action accepted - compose in middle panel');
    }

    emailFallback(accountId, accountName, opportunityId) {
        const recordId = opportunityId || accountId;
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Task',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: {
                    Subject: `Email: ${accountName}`,
                    WhatId: recordId,
                    TaskSubtype: 'Email',
                    Status: 'In Progress',
                    Priority: 'Normal',
                    Description: `Send follow-up email to ${accountName}\n\nTopics to cover:\n- `
                },
                navigationLocation: 'RELATED_LIST'
            }
        });
    }

    launchMeeting(accountId, accountName, opportunityId) {
        const recordId = opportunityId || accountId;
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Event',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: {
                    Subject: `Meeting: ${accountName}`,
                    WhatId: recordId
                }
            }
        });
    }

    launchDemo(accountId, accountName, opportunityId) {
        const recordId = opportunityId || accountId;
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Event',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: {
                    Subject: `Product Demo: ${accountName}`,
                    WhatId: recordId,
                    Description: 'Product demonstration scheduled'
                }
            }
        });
    }

    launchProposal(accountId, accountName, opportunityId) {
        const recordId = opportunityId || accountId;
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Opportunity',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: {
                    Name: `Proposal - ${accountName}`,
                    AccountId: accountId,
                    StageName: 'Proposal/Price Quote'
                }
            }
        });
    }

    launchFollowUp(accountId, accountName, opportunityId) {
        const recordId = opportunityId || accountId;
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Task',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: {
                    Subject: `Follow-up: ${accountName}`,
                    WhatId: recordId,
                    Status: 'Not Started',
                    Priority: 'Normal'
                }
            }
        });
    }



    get accountName() {
        return this.queueItem?.Account__r?.Name || '';
    }
    get employeeCount() {
        return this.queueItem?.Account__r?.Employee_Count__c || null;
    }
    get companyAgeMonths() {
        const days = this.queueItem?.Account__r?.Company_Age_in_Days__c;
        if (!days) return null;
        return Math.floor(days / 30);
    }
    // Removed badges for use cases and opportunity source (now shown in Record Details)
    get opportunityStage() {
        return this.queueItem?.Opportunity__r?.StageName;
    }
    get leadSource() {
        return this.queueItem?.Lead__r?.LeadSource || '';
    }
    get productSwitcherData() {
        return this.queueItem?.Opportunity__r?.Account_Product_Switcher_Data__c;
    }

    // Account links for Product Info
    get checkConsoleLink() {
        return this.queueItem?.Account__r?.Check_Console_Link__c || '';
    }
    get adminLink() {
        return this.queueItem?.Account__r?.Admin_Link__c || '';
    }
    get reactiveAdminLink() {
        return this.queueItem?.Account__r?.Reactive_Admin_Link__c || '';
    }
    get hasAnyAccountLinks() {
        return !!(this.checkConsoleLink || this.adminLink || this.reactiveAdminLink);
    }

    get currentPayroll() {
        return this.queueItem?.Opportunity__r?.Account_Current_Payroll__c || '';
    }

    get recordName() {
        // If there's a lead, show lead name; else if opportunity, show opportunity name; otherwise account name
        if (this.queueItem?.Lead__c) {
            return this.queueItem?.Lead__r?.Name || '';
        } else if (this.queueItem?.Opportunity__c) {
            return this.queueItem?.Opportunity__r?.Name || '';
        } else {
            return this.queueItem?.Account__r?.Name || '';
        }
    }

    get actionText() {
        if (!this.queueItem) return '';
        const objectType = this.queueItem.Lead__c ? 'Lead' : (this.queueItem.Opportunity__c ? 'Opportunity' : 'Account');
        const typeRaw = this.queueItem.Action_Type__c || '';
        let actionShort = 'Action';
        const t = typeRaw.toLowerCase();
        if (t.includes('email')) actionShort = 'Email';
        else if (t.includes('call')) actionShort = 'Call';
        else actionShort = typeRaw.replace(/_/g, ' ');
        const prefix = `${objectType} ${actionShort} for`;
        return prefix;
    }

    get actionEmoji() {
        if (!this.queueItem) return '📝';
        const actionType = this.queueItem.Action_Type__c;
        const emoji = this.getActionEmoji(actionType);
        return emoji;
    }

    get isEmailAction() {
        return this.queueItem?.Action_Type__c === 'Email';
    }

    get isEventAction() {
        return this.queueItem?.Action_Type__c === 'Event';
    }

    get isCallAction() {
        return this.queueItem?.Action_Type__c === 'Call' || 
               this.queueItem?.Action_Type__c?.includes('Call');
    }

    get meetingDispositionOptions() {
        return [
            { label: 'Attended', value: 'Attended' },
            { label: 'Missed', value: 'Missed' }
        ];
    }

    get emailCompleteMessage() {
        if (this.navigatedToEmailMessage) {
            return 'You have been navigated to the Email Message record. Please complete your email action and then click the button below to mark this action as complete.';
        } else {
            return 'You have been navigated to the Opportunity record. Please complete your email action and then click the button below to mark this action as complete.';
        }
    }

    get opportunityName() {
        return this.queueItem?.Opportunity__r?.Name || '';
    }

    get accountNameDisplay() {
        return this.queueItem?.Account__r?.Name || '';
    }

    get employeeCountDisplay() {
        return this.employeeCount || 'N/A';
    }

    get companyAgeDisplay() {
        return this.companyAgeMonths ? this.companyAgeMonths + ' months' : 'N/A';
    }

    get opportunityPayrollBuyerStage() {
        return this.queueItem?.Opportunity__r?.Payroll_Buyer_Stage__c || '';
    }

    get opportunityImplementationStatus() {
        return this.queueItem?.Opportunity__r?.Implementation_Status__c || '';
    }

    handleRecordClick() {
        // Navigate to primary record: Lead, else Opportunity, else Account
        if (this.queueItem?.Lead__c) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.queueItem.Lead__c,
                    objectApiName: 'Lead',
                    actionName: 'view'
                }
            });
        } else if (this.queueItem?.Opportunity__c) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.queueItem.Opportunity__c,
                    objectApiName: 'Opportunity',
                    actionName: 'view'
                }
            });
        } else if (this.queueItem?.Account__c) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.queueItem.Account__c,
                    objectApiName: 'Account',
                    actionName: 'view'
                }
            });
        }
    }

    handleContactClick(event) {
        if (this.queueItem?.Lead__c) {
            const leadId = this.queueItem.Lead__c;
            if (leadId) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: { recordId: leadId, objectApiName: 'Lead', actionName: 'view' }
                });
            }
            return;
        }
        const contactId = event.currentTarget.dataset.contactId;
        if (contactId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: contactId,
                    objectApiName: 'Contact',
                    actionName: 'view'
                }
            });
        }
    }

    handlePhoneClick(event) {
        // CACHE BUSTER: v3 - Try to launch Talkdesk directly
        const phoneNumber = event.currentTarget.dataset.phone;
        if (phoneNumber) {
            // Clean the phone number
            let cleanedNumber = phoneNumber.replace(/\D/g, '');
            if (!phoneNumber.startsWith('+')) {
                if (cleanedNumber.length === 10) {
                    cleanedNumber = '1' + cleanedNumber;
                }
                cleanedNumber = '+' + cleanedNumber;
            } else {
                cleanedNumber = phoneNumber;
            }

            const recordId = this.queueItem?.Account__c || this.queueItem?.Opportunity__c;
            const recordName = this.queueItem?.Account__r?.Name || this.queueItem?.Opportunity__r?.Name || 'NBA Queue Item';
            
            console.log('ATTEMPTING TALKDESK LAUNCH:', cleanedNumber);
            
            // Try multiple approaches to launch Talkdesk
            this.tryTalkdeskLaunch(cleanedNumber, recordId, recordName);
        }
    }

    tryTalkdeskLaunch(phoneNumber, recordId, recordName, tries = 0) {
        // Approach 1: Try to find and click existing Talkdesk dial button
        const talkdeskButtons = document.querySelectorAll('[data-action*="dial"], [data-action*="call"], [title*="Call"], [title*="Dial"]');
        if (talkdeskButtons.length > 0) {
            console.log('Found Talkdesk buttons, clicking first one');
            talkdeskButtons[0].click();
            this.showToast('Call Initiated', `Calling ${phoneNumber}`, 'info');
            return;
        }

        // Approach 2: Try to trigger Salesforce's native phone field click
        const phoneFields = document.querySelectorAll('a[data-aura-class="uiOutputPhone"], a[data-field-type="phone"]');
        if (phoneFields.length > 0) {
            console.log('Found phone fields, clicking first one');
            phoneFields[0].click();
            this.showToast('Call Initiated', `Calling ${phoneNumber}`, 'info');
            return;
        }

        // One-time delayed retry to allow DOM to settle (mirrors Opp reliability)
        if (tries < 1) {
            setTimeout(() => this.tryTalkdeskLaunch(phoneNumber, recordId, recordName, tries + 1), 300);
            return;
        }

        // Fallback: Show phone number and navigate to record
        console.log('All Talkdesk launch attempts failed, using fallback');
        this.showToast('Phone Number', `${phoneNumber}`, 'info');
        if (this.navigateOnAccept && recordId) {
            setTimeout(() => {
                this.showToast('Navigation', `Navigating to ${recordName} for click-to-call`, 'info');
                this.navigateToRecord(recordId);
            }, 2000);
        }
    }

    navigateToRecord(recordId) {
        // Navigate to the record where native Salesforce click-to-call will work
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }

    handleNotSurfacedRecordClick(event) {
        const id = event.currentTarget?.dataset?.id;
        if (!id) return;
        this.navigateToRecord(id);
    }



    launchProjectInitiationFlow(opportunityId, queueItemId) {
        if (!opportunityId) return;
        const apiName = this.FLOW_API_PROJECT_INITIATION;
        this.launchFlowWithInputs(apiName, opportunityId, queueItemId);
    }

    launchClosedLostFlow(opportunityId, queueItemId) {
        if (!opportunityId) return;
        const apiName = this.FLOW_API_CLOSED_LOST;
        this.launchFlowWithInputs(apiName, opportunityId, queueItemId);
    }

    launchFlowWithInputs(apiName, opportunityId, queueItemId) {
        this.openEmbeddedFlow(apiName, opportunityId, queueItemId);
    }

    openEmbeddedFlow(apiName, recordId, queueItemId) {
        this.embeddedFlowApiName = apiName;
        this.embeddedFlowRecordId = recordId;
        this.embeddedFlowQueueItemId = queueItemId;
        this.showEmbeddedFlow = true;
    }

    async handleEmbeddedFlowComplete(evt) {
        try {
            // finalize on flow finish to mark Accepted/Completed
            const qi = this.embeddedFlowQueueItemId;
            if (qi) {
                await finalizeQueueItem({ queueItemId: qi });
            }
        } catch (e) {
            // non-blocking
        }
        this.showEmbeddedFlow = false;
        this.embeddedFlowApiName = null;
        this.embeddedFlowRecordId = null;
        this.embeddedFlowQueueItemId = null;
        // Refresh queue to pull next item
        this.loadQueueItem();
        this.showToast('Success', 'Flow completed', 'success');
    }

    // Removed embedded flow helpers

    handleOpportunityClick() {
        if (this.queueItem?.Opportunity__c) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.queueItem.Opportunity__c,
                    objectApiName: 'Opportunity',
                    actionName: 'view'
                }
            });
        }
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
        if (this.isNotSurfacedTab) {
            this.loadNotSurfaced();
        }
        if (this.isActivityTab) {
            this.loadActivities();
        }
    }

    get isContactTab() {
        return this.activeTab === 'contact';
    }
    get isProductTab() {
        return this.activeTab === 'product';
    }
    get isActivityTab() {
        return this.activeTab === 'activity';
    }
    get isUpNextTab() {
        return this.activeTab === 'upnext';
    }
    get isNotSurfacedTab() {
        return this.activeTab === 'notsurfaced';
    }

    get contactTabClass() {
        return this.isContactTab ? 'nba-widget-tab active' : 'nba-widget-tab';
    }
    get productTabClass() {
        return this.isProductTab ? 'nba-widget-tab active' : 'nba-widget-tab';
    }
    get upNextTabClass() {
        return this.isUpNextTab ? 'nba-widget-tab active' : 'nba-widget-tab';
    }
    get notSurfacedTabClass() {
        return this.isNotSurfacedTab ? 'nba-widget-tab active' : 'nba-widget-tab';
    }
    get activityTabClass() {
        return this.isActivityTab ? 'nba-widget-tab active' : 'nba-widget-tab';
    }

    // Activity record context: use Opportunity if present; else Account; else Lead
    get activityRecordId() {
        if (!this.queueItem) return null;
        return this.queueItem.Opportunity__c || this.queueItem.Account__c || this.queueItem.Lead__c || null;
    }

    @track upcomingActivities = [];
    @track pastActivities = [];

    async loadActivities() {
        const id = this.activityRecordId;
        if (!id) { this.upcomingActivities = []; this.pastActivities = []; return; }
        try {
            const data = await getActivities({ recordId: id });
            const up = Array.isArray(data?.upcoming) ? data.upcoming : [];
            const past = Array.isArray(data?.past) ? data.past : [];
            this.upcomingActivities = up.map((row) => {
                const isOverdue = this.isOverdue(row);
                return {
                    ...row,
                    display: this.formatActivityDisplay(row),
                    isOverdue,
                    overdueStyle: isOverdue ? 'color:#c23934;' : ''
                };
            });
            this.pastActivities = past.map((row) => ({
                ...row,
                display: this.formatActivityDisplay(row)
            }));
        } catch (e) {
            this.upcomingActivities = [];
            this.pastActivities = [];
        }
    }

    isOverdue(row) {
        try {
            const dt = row?.date || row?.start || null;
            if (!dt) return false;
            const due = new Date(dt).getTime();
            return due < Date.now();
        } catch (e) {
            return false;
        }
    }

    formatActivityDisplay(row) {
        const subject = row?.subject || '';
        const dateVal = row?.start || row?.date || null;
        if (!dateVal) return subject;
        try {
            const d = new Date(dateVal);
            const opts = { month: '2-digit', day: '2-digit', year: 'numeric', hour: 'numeric', minute: '2-digit' };
            const formatted = d.toLocaleString(undefined, opts);
            return `${subject} — ${formatted}`;
        } catch (e) {
            return `${subject}`;
        }
    }

    openOpenActivities = () => {
        const id = this.activityRecordId;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, actionName: 'view' },
            state: { tabName: 'related' }
        });
    }

    openActivityHistory = () => {
        const id = this.activityRecordId;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, actionName: 'view' },
            state: { tabName: 'related' }
        });
    }

    async loadNotSurfaced() {
        try {
            const rows = await listNotSurfacedItems({ userId: this.currentUserId, limitSize: 50 });
            this.notSurfaced = Array.isArray(rows) ? rows : [];
        } catch (e) {
            console.error('Error loading not surfaced items', e);
            this.notSurfaced = [];
        }
    }
    get hasProductUsage() {
        if (!this.queueItem) return false;
        return this.queueItem.Break_Preferences_Engaged__c || 
               this.queueItem.Department_Management_Engaged__c || 
               this.queueItem.Geofencing_Engaged__c || 
               this.queueItem.Hiring_Engaged__c || 
               this.queueItem.Hrdocs_Engaged__c || 
               this.queueItem.Manager_Log_Engaged__c || 
               this.queueItem.Messaging_Engaged__c || 
               this.queueItem.Mobile_Time_Tracking_Engaged__c || 
               this.queueItem.Oam_Activity__c || 
               this.queueItem.Overtime_Preferences_Engaged__c || 
               this.queueItem.Scheduling_Engaged__c || 
               this.queueItem.Shift_Notes_Engaged__c || 
               this.queueItem.Shift_Trades_Engaged__c || 
               this.queueItem.Time_Offs_Engaged__c || 
               this.queueItem.Time_Tracking_Engaged__c;
    }

    get isCallScheduled() { return this.dismissalCategory === 'Call Scheduled'; }
    get isTimeZoneSnooze() { return this.dismissalCategory === 'Time Zone'; }
    get isOtherDismissal() { return this.dismissalCategory === 'Other'; }

    // Helper to check if we should use NBA Queue contact info vs Account primary contact
    get shouldUseNBAQueueContact() {
        if (!this.queueItem?.Opportunity__c) {
            return true; // No opportunity, use NBA Queue contact
        }
        const stage = this.queueItem?.Opportunity__r?.StageName;
        const shouldUse = stage === 'New Opportunity' || stage === 'Attempted';
        return shouldUse;
    }

    // Contact information getters that check Opportunity stage
    get displayContactPerson() {
        if (this.queueItem?.Lead__c) {
            return this.queueItem?.Lead__r?.Name || '';
        }
        if (this.shouldUseNBAQueueContact && this.queueItem?.Best_Person_to_Call__c) {
            const nbaContact = this.queueItem?.Best_Person_to_Call__r?.Name || '';
            return nbaContact;
        } else {
            const oppContact = this.opportunityPrimaryContact?.contactName || '';
            return oppContact;
        }
    }

    get displayContactId() {
        if (this.queueItem?.Lead__c) {
            return this.queueItem.Lead__c || '';
        }
        if (this.shouldUseNBAQueueContact && this.queueItem?.Best_Person_to_Call__c) {
            return this.queueItem?.Best_Person_to_Call__c || '';
        } else {
            return this.opportunityPrimaryContact?.contactId || '';
        }
    }

    get displayContactEmail() {
        if (this.queueItem?.Lead__c) {
            return this.queueItem?.Lead__r?.Email || '';
        }
        if (this.shouldUseNBAQueueContact && this.queueItem?.Best_Person_to_Call__c) {
            const nbaEmail = this.queueItem?.Best_Person_to_Call__r?.Email || '';
            return nbaEmail;
        } else {
            const oppEmail = this.opportunityPrimaryContact?.contactEmail || '';
            return oppEmail;
        }
    }

    get displayContactPhone() {
        // Lead-based queue item: use Lead.Phone (fallback to Lead.MobilePhone)
        if (this.queueItem?.Lead__c) {
            const leadPhone = this.queueItem?.Lead__r?.Phone || this.queueItem?.Lead__r?.MobilePhone || '';
            return leadPhone || '';
        }
        // If the NBA Queue record has a related Opportunity
        if (this.queueItem?.Opportunity__c) {
            const stage = this.queueItem?.Opportunity__r?.StageName;
            if (stage === 'New Opportunity' || stage === 'Attempted') {
                if (this.queueItem?.Best_Person_to_Call__c) {
                    const nbaPhone = this.queueItem?.Best_Number_to_Call__c;
                    if (nbaPhone) {
                        return nbaPhone;
                    }
                }
                const oppPhone = this.opportunityPrimaryContact?.contactPhone || '';
                return oppPhone;
            } else {
                const oppPhone = this.opportunityPrimaryContact?.contactPhone || '';
                return oppPhone;
            }
        } else {
            if (this.queueItem?.Best_Person_to_Call__c) {
                const nbaPhone = this.queueItem?.Best_Number_to_Call__c;
                if (nbaPhone) {
                    return nbaPhone;
                }
            }
            return this.opportunityPrimaryContact?.contactPhone || '';
        }
    }

    get displayTimeZone() {
        if (!this.queueItem) return '';
        
        // For Opportunity calls, show Opportunity Time Zone, otherwise show Account Time Zone
        if (this.queueItem.Opportunity__c && this.queueItem.Opportunity__r?.Time_Zone__c) {
            return this.queueItem.Opportunity__r.Time_Zone__c;
        }
        
        if (this.queueItem.Account__r?.Time_Zone__c) {
            return this.queueItem.Account__r.Time_Zone__c;
        }
        
        return '';
    }

    // Priority score display getters
    get showPriorityScore() {
        return this.originalScore != null && this.adjustedScore != null;
    }

    get priorityScoreDisplay() {
        if (!this.showPriorityScore) return '';
        return `${this.adjustedScore.toFixed(1)}`;
    }

    get originalScoreDisplay() {
        if (!this.originalScore) return '';
        return `${this.originalScore.toFixed(1)}`;
    }

    get hasMultipliers() {
        return this.webUsageApplied || this.bestTimeApplied;
    }

    get multiplierText() {
        let text = '';
        if (this.webUsageApplied) {
            text += `Web Usage (1.25x)`;
        }
        if (this.bestTimeApplied) {
            if (text) text += ', ';
            text += `Best Time (1.2x)`;
        }
        return text;
    }

    get priorityScoreClass() {
        if (!this.showPriorityScore) return '';
        if (this.adjustedScore >= 80) return 'priority-high';
        if (this.adjustedScore >= 60) return 'priority-medium';
        return 'priority-low';
    }

    // Helper method to get the correct phone number for call actions
    async getContactPhoneForCall(queueItem) {
        console.log('getContactPhoneForCall called with queueItem:', queueItem);
        console.log('queueItem.Best_Number_to_Call__c:', queueItem?.Best_Number_to_Call__c);
        console.log('queueItem.Best_Person_to_Call__c:', queueItem?.Best_Person_to_Call__c);
        
        // If the NBA Queue record has a related Opportunity
        if (queueItem?.Opportunity__c) {
            const stage = queueItem?.Opportunity__r?.StageName;
            if (stage === 'New Opportunity' || stage === 'Attempted') {
                if (queueItem?.Best_Person_to_Call__c) {
                    const nbaPhone = queueItem?.Best_Number_to_Call__c;
                    if (nbaPhone) {
                        return nbaPhone;
                    }
                }
                return this.opportunityPrimaryContact?.contactPhone || this.displayContactPhone || null;
            } else {
                return this.opportunityPrimaryContact?.contactPhone || this.displayContactPhone || null;
            }
        } else if (queueItem?.Lead__c) {
            // Lead-first: prefer Best Number; fallback to Lead phone; final fallback to displayed phone
            if (queueItem?.Best_Number_to_Call__c) {
                return queueItem.Best_Number_to_Call__c;
            }
            const leadPhone = queueItem?.Lead__r?.Phone || queueItem?.Lead__r?.MobilePhone || null;
            return leadPhone || this.displayContactPhone || null;
        } else {
            if (queueItem?.Best_Person_to_Call__c) {
                const nbaPhone = queueItem?.Best_Number_to_Call__c;
                if (nbaPhone) {
                    return nbaPhone;
                }
            }
            if (this.opportunityPrimaryContact?.contactPhone) {
                return this.opportunityPrimaryContact.contactPhone;
            }
            try {
                const accountContact = await getAccountPrimaryContact({ accountId: queueItem?.Account__c });
                return accountContact?.contactPhone || this.displayContactPhone || null;
            } catch (error) {
                console.error('Error getting account primary contact phone:', error);
                try {
                    const accountPhone = await this.getAccountPhone(queueItem?.Account__c);
                    return accountPhone || this.displayContactPhone || null;
                } catch (e2) {
                    return this.displayContactPhone || null;
                }
            }
        }
    }

    // Opportunity Description getters for Rep Notes section
    get hasOpportunityDescription() {
        return this.queueItem && 
               this.queueItem.Opportunity__c && 
               this.queueItem.Opportunity__r && 
               this.queueItem.Opportunity__r.Description;
    }

    get opportunityDescription() {
        if (this.hasOpportunityDescription) {
            return this.queueItem.Opportunity__r.Description;
        }
        return '';
    }

    get upNextRecordId() {
        if (!this.upNextItem) return null;
        return this.upNextItem.Opportunity__c || this.upNextItem.Lead__c || this.upNextItem.Account__c || null;
    }
    get upNextObjectApiName() {
        if (!this.upNextItem) return null;
        if (this.upNextItem.Lead__c) return 'Lead';
        if (this.upNextItem.Opportunity__c) return 'Opportunity';
        if (this.upNextItem.Account__c) return 'Account';
        return null;
    }

    handleUpNextRecordClick = (e) => {
        const id = e.currentTarget?.dataset?.id || this.upNextRecordId;
        const api = e.currentTarget?.dataset?.object || this.upNextObjectApiName;
        if (!id || !api) return;
        this.navigateToRecord(id, api);
    }

    get isUpNextLead() {
        return !!(this.upNextItem && this.upNextItem.Lead__c);
    }
    get isUpNextOpp() {
        return !!(this.upNextItem && this.upNextItem.Opportunity__c && !this.upNextItem.Lead__c);
    }
    get isUpNextAccount() {
        return !!(this.upNextItem && !this.upNextItem.Opportunity__c && !this.upNextItem.Lead__c && this.upNextItem.Account__c);
    }

    // Email action handlers
    async handleEmailAccept() {
        try {
            this.isLoading = true;
            const result = await handleEmailAccept({ queueItemId: this.queueItem.Id });
            
            if (result.success) {
                // Store navigation info for dynamic message
                this.navigatedToEmailMessage = !!result.emailMessageId;
                
                // Navigate to email message if available, otherwise opportunity
                if (result.emailMessageId) {
                    this.navigateToRecord(result.emailMessageId);
                } else {
                    this.navigateToRecord(result.opportunityId);
                }
                // Show complete modal
                this.showEmailCompleteModal = true;
            }
        } catch (error) {
            console.error('Error accepting email action:', error);
            this.showToast('Error', 'Failed to accept email action', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleEmailComplete() {
        try {
            this.isLoading = true;
            await completeEmailAction({ queueItemId: this.queueItem.Id });
            this.showEmailCompleteModal = false;
            this.showToast('Success', 'Email action completed', 'success');
            this.loadQueueItem();
        } catch (error) {
            console.error('Error completing email action:', error);
            this.showToast('Error', 'Failed to complete email action', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Event action handlers
    async handleEventAccept() {
        try {
            this.isLoading = true;
            const result = await handleEventAccept({ queueItemId: this.queueItem.Id });
            
            if (result.success) {
                // Navigate to event if available, otherwise opportunity
                if (result.eventId) {
                    this.navigateToRecord(result.eventId);
                } else {
                    this.navigateToRecord(result.opportunityId);
                }
                // Show meeting disposition modal directly (skip contact confirmation)
                this.showMeetingDispositionModal = true;
            }
        } catch (error) {
            console.error('Error accepting event action:', error);
            this.showToast('Error', 'Failed to accept event action', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleMeetingDispositionSave() {
        try {
            this.isLoading = true;
            await saveMeetingDisposition({ 
                queueItemId: this.queueItem.Id,
                meetingDisposition: this.meetingDisposition,
                meetingNotes: this.meetingNotes
            });
            this.showMeetingDispositionModal = false;
            this.showToast('Success', 'Meeting disposition saved', 'success');
            this.loadQueueItem();
        } catch (error) {
            console.error('Error saving meeting disposition:', error);
            this.showToast('Error', 'Failed to save meeting disposition', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleMeetingDispositionChange(event) {
        this.meetingDisposition = event.target.value;
    }

    handleMeetingNotesChange(event) {
        this.meetingNotes = event.target.value;
    }

    handleEmailCompleteCancel() {
        this.showEmailCompleteModal = false;
    }

    handleMeetingDispositionCancel() {
        this.showMeetingDispositionModal = false;
        this.meetingDisposition = '';
        this.meetingNotes = '';
    }
}