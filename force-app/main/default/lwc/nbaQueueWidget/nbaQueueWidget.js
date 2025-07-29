import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { publish, MessageContext } from 'lightning/messageService';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadStyle } from 'lightning/platformResourceLoader';
import PlusJakartaSans from '@salesforce/resourceUrl/PlusJakartaSans';
import getNextQueueItem from '@salesforce/apex/NBAQueueManager.getNextQueueItem';
import getNextQueueItemWithDetails from '@salesforce/apex/NBAQueueManager.getNextQueueItemWithDetails';
import markAsViewed from '@salesforce/apex/NBAQueueManager.markAsViewed';
import acceptAction from '@salesforce/apex/NBAQueueManager.acceptAction';
import dismissAction from '@salesforce/apex/NBAQueueManager.dismissAction';
import updateCallDisposition from '@salesforce/apex/NBAQueueManager.updateCallDispositionWithQueueId';
import cancelCallDisposition from '@salesforce/apex/NBAQueueManager.cancelCallDisposition';
import getOpportunityPrimaryContact from '@salesforce/apex/NBAQueueManager.getOpportunityPrimaryContact';
import getAccountPhoneNumber from '@salesforce/apex/NBAQueueManager.getAccountPhoneNumber';
import userId from '@salesforce/user/Id';

export default class NbaQueueWidget extends NavigationMixin(LightningElement) {
    @api panelHeight = 400;
    @track queueItem = null;
    @track isLoading = false;
    @track showCallDispositionModal = false;
    @track showDismissModal = false;
    @track selectedItem = null;
    @track currentTaskId = null;
    @track callDisposition = '';
    @track callNotes = '';
    @track dismissReason = '';
    @track currentPhoneNumber = '';
    @track activeTab = 'details';
    @track opportunityPrimaryContact = null;
    @track lastRefreshTime = null;
    @track fontLoaded = false;
    @track showCallDispositionForm = false;
    @track showDismissForm = false;
    @track pendingAction = null; // Track pending action for when widget is minimized
    @track isBlinking = false; // For alerting when new action comes in
    
    @wire(MessageContext) messageContext;

    currentUserId = userId;
    refreshTimer = null;
    refreshInterval = 30000; // 30 seconds

    async connectedCallback() {
        // Load the Plus Jakarta Sans font first
        await this.loadFonts();
        
        this.loadQueueItem();
        this.startAutoRefresh();
        
        // Listen for page visibility changes to detect when widget is minimized
        document.addEventListener('visibilitychange', this.handleVisibilityChange.bind(this));
        
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
        
        // Update last refresh time
        this.lastRefreshTime = new Date();
        
        try {
            const result = await getNextQueueItemWithDetails({ userId: this.currentUserId });
            console.log('Queue item data received:', result);
            
            if (result && result.queueItem) {
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
                    formattedLastCallDate: this.formatDateTime(result.queueItem.Last_Call_Date__c),
                    actionIcon: this.getActionIcon(result.queueItem.Action_Type__c),
                    isPayrollAction: this.isPayrollAction(result.queueItem.Action_Type__c),
                    featuresList: this.formatFeatureUsage(result.queueItem.Feature_Usage__c),
                    isExpanded: false,
                    expandIcon: 'utility:chevronright',
                    expandText: 'Show'
                };
                
                // Set default tab based on whether there's an Opportunity
                if (result.queueItem.Opportunity__c) {
                    this.activeTab = 'details';
                } else {
                    this.activeTab = 'contact';
                }
                
                // Mark the record as viewed (first time only)
                try {
                    await markAsViewed({ queueItemId: result.queueItem.Id });
                    console.log('Record marked as viewed');
                } catch (error) {
                    console.error('Error marking record as viewed:', error);
                }
                
                // Load opportunity primary contact if there's an opportunity (needed for fallback)
                console.log('Checking if should load opportunity primary contact...');
                console.log('Opportunity ID:', result.queueItem.Opportunity__c);
                
                if (result.queueItem.Opportunity__c) {
                    try {
                        console.log('Loading opportunity primary contact for ID:', result.queueItem.Opportunity__c);
                        const contactData = await getOpportunityPrimaryContact({ opportunityId: result.queueItem.Opportunity__c });
                        this.opportunityPrimaryContact = contactData;
                        console.log('Opportunity primary contact loaded:', contactData);
                        
                        // Pre-populate call notes with opportunity description if available
                        if (result.queueItem.Opportunity__r && result.queueItem.Opportunity__r.Description) {
                            this.callNotes = result.queueItem.Opportunity__r.Description;
                            console.log('Pre-populated call notes with opportunity description:', this.callNotes);
                        } else {
                            this.callNotes = ''; // Clear call notes if no opportunity description
                        }
                    } catch (error) {
                        console.error('Error loading opportunity primary contact:', error);
                        this.opportunityPrimaryContact = null;
                        this.callNotes = ''; // Clear call notes on error
                    }
                } else {
                    console.log('No opportunity - setting primary contact to null');
                    this.opportunityPrimaryContact = null;
                    this.callNotes = ''; // Clear call notes if no opportunity
                }
                
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
    }

    startAutoRefresh() {
        console.log('Starting auto-refresh timer - will refresh every 30 seconds');
        this.refreshTimer = setInterval(() => {
            if (!this.isLoading && !this.showCallDispositionModal) {
                console.log('Auto-refresh triggered - checking for updated queue items...');
                this.loadQueueItem().catch(error => {
                    console.error('Auto-refresh failed: ', error);
                });
            } else {
                console.log('Auto-refresh skipped - component is loading or modal is open');
            }
        }, this.refreshInterval);
    }

    stopAutoRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = null;
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

    handleAcceptAction(event) {
        const itemId = event.currentTarget?.dataset?.id || (event.target && event.target.dataset && event.target.dataset.id);
        if (itemId && (!this.queueItem || this.queueItem.Id !== itemId)) {
            // If the queueItem is not the one being acted on, fetch it (future-proofing for lists)
            // For now, just use the current queueItem
        }
        this.selectedItem = this.queueItem;
        this.executeAcceptAction();
    }

    handleDismissAction(event) {
        console.log('Dismiss action triggered');
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
    submitDismissReason() {
        // Validate that dismissal reason is provided
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

        const actionType = this.selectedItem.Action_Type__c;
        const accountId = this.selectedItem.Account__c;
        const accountName = this.selectedItem.Account__r.Name;
        const currentItem = this.selectedItem;

        console.log('Action type:', actionType);
        console.log('Current modal states - showDismissModal:', this.showDismissModal, 'showCallDispositionModal:', this.showCallDispositionModal);

        acceptAction({ queueItemId: this.selectedItem.Id, additionalNotes: '' })
            .then((taskId) => {
                console.log('Accept action successful, task ID:', taskId);
                this.showToast('Success', 'Action accepted and task created', 'success');
                
                // Store task ID for call disposition if needed
                this.currentTaskId = taskId;
                
                if (actionType.includes('Call')) {
                    console.log('Action is a call type, launching call and showing disposition form');
                    console.log('Queue item data for pre-population:', {
                        hasQueueItem: !!this.queueItem,
                        hasOpportunity: !!(this.queueItem && this.queueItem.Opportunity__r),
                        opportunityDescription: this.queueItem?.Opportunity__r?.Description,
                        fullQueueItem: this.queueItem
                    });
                    
                    // Preserve any pre-populated call notes from the opportunity description BEFORE showing form
                    if (this.queueItem && this.queueItem.Opportunity__r && this.queueItem.Opportunity__r.Description) {
                        this.callNotes = this.queueItem.Opportunity__r.Description;
                        console.log('Preserved opportunity description in call notes:', this.callNotes);
                    } else {
                        console.log('No opportunity description found to pre-populate');
                        this.callNotes = ''; // Ensure it's empty if no description
                    }
                    
                    // Launch the call first
                    this.launchAction(currentItem);
                    // Then show call disposition form
                    this.showCallDispositionForm = true;
                    this.pendingAction = 'call';
                } else {
                    console.log('Action is not a call type, launching action');
                    this.launchAction(currentItem);
                    // Load next queue item after non-call action
                    return this.loadQueueItem();
                }
            })
            .catch(error => {
                console.error('Accept action error:', error);
                this.showToast('Error', error.body?.message || 'Failed to accept action', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
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

    handleCallDispositionSave() {
        if (!this.callDisposition) {
            this.showToast('Error', 'Please select a call disposition', 'error');
            return;
        }

        this.isLoading = true;

        updateCallDisposition({ 
            taskId: this.currentTaskId,
            queueItemId: this.selectedItem.Id,
            disposition: this.callDisposition,
            callNotes: this.callNotes
        })
            .then(() => {
                this.showToast('Success', 'Call disposition saved', 'success');
                this.closeCallDispositionFormSuccess();
                // Load next queue item after saving disposition
                return this.loadQueueItem();
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Failed to save call disposition', 'error');
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
            'Meeting': 'utility:event',
            'Follow_Up': 'utility:follow_up',
            'Demo': 'utility:screen_share',
            'Proposal': 'utility:contract',
            'Payroll Opportunity Call': 'utility:moneybag',
            'Payroll Prospecting Call': 'utility:currency'
        };
        return iconMap[actionType] || 'utility:task';
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
        const actionType = queueItem.Action_Type__c;
        const accountId = queueItem.Account__c;
        const accountName = queueItem.Account__r.Name;
        const opportunityId = queueItem.Opportunity__c;

        switch(actionType) {
            case 'Call':
            case 'Payroll Opportunity Call':
            case 'Payroll Prospecting Call':
                // Use the same contact logic as the display
                const phoneNumber = await this.getContactPhoneForCall(queueItem);
                this.launchCall(accountId, accountName, phoneNumber, opportunityId);
                break;
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
                this.navigateToRecord(opportunityId || accountId);
                break;
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

                // Set current phone number for call disposition
                this.currentPhoneNumber = cleanedNumber;

                // New: Try to trigger click-to-call
                this.triggerClickToCall(cleanedNumber);
                // Show phone number in toast
                this.showToast('Phone Number', `${cleanedNumber}`, 'info');
                // Navigate to the record where they can use native Salesforce click-to-call
                setTimeout(() => {
                    this.showToast('Navigation', `Navigating to ${accountName} for click-to-call`, 'info');
                    this.navigateToRecord(opportunityId || accountId);
                }, 2000);
            } else {
                console.log('No phone number available');
                this.currentPhoneNumber = 'No phone number available';
                this.showToast('No Phone Number', `No phone number found for ${accountName}`, 'warning');
                this.navigateToRecord(opportunityId || accountId);
            }
        };
        if (phoneNumber) {
            callWithNumber(phoneNumber);
        } else {
            console.log('No phone number available from getContactPhoneForCall');
            this.currentPhoneNumber = 'No phone number available';
            this.showToast('No Phone Number', `No phone number found for ${accountName}`, 'warning');
            this.navigateToRecord(opportunityId || accountId);
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
        console.log('Launching email for:', accountName, accountId);
        const recordId = opportunityId || accountId;
        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: {
                apiName: 'Global.SendEmail'
            },
            state: {
                recordId: recordId,
                defaultFieldValues: {
                    Subject: `Follow-up: ${accountName}`,
                    HtmlBody: `<p>Dear ${accountName} team,</p><p>I wanted to follow up regarding...</p>`,
                    RelatedToId: recordId
                }
            }
        }).catch(error => {
            console.log('Global.SendEmail failed, trying fallback');
            this.emailFallback(accountId, accountName, opportunityId);
        });
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
    get useCasePayroll() {
        return this.queueItem?.Account__r?.Use_Case_Payroll__c;
    }
    get useCaseScheduling() {
        return this.queueItem?.Account__r?.Use_Case_Scheduling__c;
    }
    get useCaseTimeTracking() {
        return this.queueItem?.Account__r?.Use_Case_Time_Tracking__c;
    }
    get opportunitySource() {
        return this.queueItem?.Opportunity__r?.Source__c;
    }
    get opportunityStage() {
        return this.queueItem?.Opportunity__r?.StageName;
    }
    get payrollBuyerStage() {
        return this.queueItem?.Opportunity__r?.Payroll_Buyer_Stage__c;
    }
    get productSwitcherData() {
        return this.queueItem?.Opportunity__r?.Account_Product_Switcher_Data__c;
    }

    get currentPayroll() {
        // First try Most Recent Payroll Provider, then fall back to Opportunity's Account Current Payroll
        return this.queueItem?.Most_Recent_Payroll_Provider__c || 
               this.queueItem?.Opportunity__r?.Account_Current_Payroll__c || 
               '';
    }

    get recordName() {
        // If there's an opportunity, show opportunity name, otherwise show account name
        if (this.queueItem?.Opportunity__c) {
            return this.queueItem?.Opportunity__r?.Name || '';
        } else {
            return this.queueItem?.Account__r?.Name || '';
        }
    }

    get actionText() {
        // If there's an opportunity, show "Payroll opportunity call for", otherwise show "Account call for"
        if (this.queueItem?.Opportunity__c) {
            return 'Payroll opportunity call for';
        } else {
            return 'Account call for';
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
        // If there's an opportunity, navigate to opportunity, otherwise navigate to account
        if (this.queueItem?.Opportunity__c) {
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

    tryTalkdeskLaunch(phoneNumber, recordId, recordName) {
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

        // Approach 3: Try to use Lightning Message Service to communicate with Talkdesk
        try {
            if (this.messageContext) {
                const message = {
                    recordId: recordId,
                    recordName: recordName,
                    phoneNumber: phoneNumber,
                    action: 'dial'
                };
                
                publish(this.messageContext, 'TALKDESK_DIAL', message);
                console.log('Published TALKDESK_DIAL message');
                this.showToast('Call Initiated', `Calling ${phoneNumber}`, 'info');
                return;
            }
        } catch (error) {
            console.log('Lightning Message Service failed:', error);
        }

        // Approach 4: Try to dispatch a custom event that Talkdesk might be listening for
        try {
            const dialEvent = new CustomEvent('talkdesk:dial', {
                detail: {
                    phoneNumber: phoneNumber,
                    recordId: recordId,
                    recordName: recordName
                },
                bubbles: true,
                cancelable: true
            });
            
            document.dispatchEvent(dialEvent);
            console.log('Dispatched talkdesk:dial event');
            this.showToast('Call Initiated', `Calling ${phoneNumber}`, 'info');
            return;
        } catch (error) {
            console.log('Custom event dispatch failed:', error);
        }

        // Fallback: Show phone number and navigate to record
        console.log('All Talkdesk launch attempts failed, using fallback');
        this.showToast('Phone Number', `${phoneNumber}`, 'info');
        
        if (recordId) {
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
    }

    get isDetailsTab() {
        return this.activeTab === 'details';
    }
    get isContactTab() {
        return this.activeTab === 'contact';
    }
    get isProductTab() {
        return this.activeTab === 'product';
    }

    get detailsTabClass() {
        return this.isDetailsTab ? 'nba-widget-tab active' : 'nba-widget-tab';
    }

    get contactTabClass() {
        return this.isContactTab ? 'nba-widget-tab active' : 'nba-widget-tab';
    }
    get productTabClass() {
        return this.isProductTab ? 'nba-widget-tab active' : 'nba-widget-tab';
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

    // Helper to check if we should use NBA Queue contact info vs Account primary contact
    get shouldUseNBAQueueContact() {
        if (!this.queueItem?.Opportunity__c) {
            console.log('No opportunity, using NBA Queue contact');
            return true; // No opportunity, use NBA Queue contact
        }
        const stage = this.queueItem?.Opportunity__r?.StageName;
        const shouldUse = stage === 'New Opportunity' || stage === 'Attempted';
        console.log('Opportunity stage:', stage, 'Should use NBA Queue contact:', shouldUse);
        return shouldUse;
    }

    // Contact information getters that check Opportunity stage
    get displayContactPerson() {
        if (this.shouldUseNBAQueueContact) {
            const nbaContact = this.queueItem?.Best_Person_to_Call__r?.Name || '';
            console.log('Using NBA Queue contact person:', nbaContact);
            return nbaContact;
        } else {
            const oppContact = this.opportunityPrimaryContact?.contactName || '';
            console.log('Using Opportunity primary contact person:', oppContact);
            return oppContact;
        }
    }

    get displayContactId() {
        if (this.shouldUseNBAQueueContact) {
            return this.queueItem?.Best_Person_to_Call__c || '';
        } else {
            return this.opportunityPrimaryContact?.contactId || '';
        }
    }

    get displayContactEmail() {
        if (this.shouldUseNBAQueueContact) {
            const nbaEmail = this.queueItem?.Best_Person_to_Call__r?.Email || '';
            console.log('Using NBA Queue contact email:', nbaEmail);
            return nbaEmail;
        } else {
            const oppEmail = this.opportunityPrimaryContact?.contactEmail || '';
            console.log('Using Opportunity primary contact email:', oppEmail);
            return oppEmail;
        }
    }

    get displayContactPhone() {
        // If the NBA Queue record has a related Opportunity
        if (this.queueItem?.Opportunity__c) {
            const stage = this.queueItem?.Opportunity__r?.StageName;
            
            // If the Opportunity's StageName is "New Opportunity" or "Attempted"
            if (stage === 'New Opportunity' || stage === 'Attempted') {
                // Use the "Best Number to Call" field from the NBA Queue record
                const nbaPhone = this.queueItem?.Best_Number_to_Call__c;
                if (nbaPhone) {
                    console.log('Using NBA Queue Best Number to Call:', nbaPhone);
                    return nbaPhone;
                } else {
                    // If that field is null, fall back to the phone number of the Primary Contact on the related Opportunity
                    const oppPhone = this.opportunityPrimaryContact?.contactPhone || '';
                    console.log('NBA Queue phone is null, falling back to Opportunity primary contact phone:', oppPhone);
                    return oppPhone;
                }
            } else {
                // If the Opportunity's StageName is anything else, ignore the "Best Number to Call" field
                // Use the phone number of the Primary Contact on the related Opportunity
                const oppPhone = this.opportunityPrimaryContact?.contactPhone || '';
                console.log('Using Opportunity primary contact phone (other stages):', oppPhone);
                return oppPhone;
            }
        } else {
            // If the NBA Queue record does not have a related Opportunity
            // First, try to use the "Best Number to Call" field from the NBA Queue record
            const nbaPhone = this.queueItem?.Best_Number_to_Call__c;
            if (nbaPhone) {
                console.log('Using NBA Queue Best Number to Call (no opportunity):', nbaPhone);
                return nbaPhone;
            } else {
                // If that is null, we can't get the account phone in a getter (async)
                // The actual account phone will be resolved in getContactPhoneForCall
                console.log('NBA Queue phone is null, will fall back to Account primary contact phone in call logic');
                return ''; // Empty string for display, actual phone will be resolved during call
            }
        }
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
        // If the NBA Queue record has a related Opportunity
        if (queueItem?.Opportunity__c) {
            const stage = queueItem?.Opportunity__r?.StageName;
            
            // If the Opportunity's StageName is "New Opportunity" or "Attempted"
            if (stage === 'New Opportunity' || stage === 'Attempted') {
                // Use the "Best Number to Call" field from the NBA Queue record
                const nbaPhone = queueItem?.Best_Number_to_Call__c;
                if (nbaPhone) {
                    return nbaPhone;
                } else {
                    // If that field is null, fall back to the phone number of the Primary Contact on the related Opportunity
                    return this.opportunityPrimaryContact?.contactPhone || null;
                }
            } else {
                // If the Opportunity's StageName is anything else, ignore the "Best Number to Call" field
                // Use the phone number of the Primary Contact on the related Opportunity
                return this.opportunityPrimaryContact?.contactPhone || null;
            }
        } else {
            // If the NBA Queue record does not have a related Opportunity
            // First, try to use the "Best Number to Call" field from the NBA Queue record
            const nbaPhone = queueItem?.Best_Number_to_Call__c;
            if (nbaPhone) {
                return nbaPhone;
            } else {
                // If that is null, fall back to the phone number of the Primary Contact on the related Account
                try {
                    const accountPhone = await this.getAccountPhone(queueItem?.Account__c);
                    return accountPhone;
                } catch (error) {
                    console.error('Error getting account phone:', error);
                    return null;
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
}