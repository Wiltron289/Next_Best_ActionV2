import { LightningElement, track, wire, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import userId from '@salesforce/user/Id';
import getNextQueueItemWithDetails from '@salesforce/apex/NBAQueueManager.getNextQueueItemWithDetails';
import getUpNextItem from '@salesforce/apex/NBAQueueManager.getUpNextItem';
import acceptAction from '@salesforce/apex/NBAQueueManager.acceptAction';
import dismissAction from '@salesforce/apex/NBAQueueManager.dismissAction';
import updateCallDisposition from '@salesforce/apex/NBAQueueManager.updateCallDispositionWithQueueId';
import cancelCallDisposition from '@salesforce/apex/NBAQueueManager.cancelCallDisposition';
import getOpportunityPrimaryContact from '@salesforce/apex/NBAQueueManager.getOpportunityPrimaryContact';
import getAccountPrimaryContact from '@salesforce/apex/NBAQueueManager.getAccountPrimaryContact';
import sendQueueEmail from '@salesforce/apex/NBAQueueManager.sendQueueEmail';
import sendQueueEmailWithTemplate from '@salesforce/apex/NBAQueueManager.sendQueueEmailWithTemplate';
import listEmailTemplates from '@salesforce/apex/NBAQueueManager.listEmailTemplates';
// Removed renderEmailTemplate usage to avoid incompatible API in this org
import getAccountPhoneNumber from '@salesforce/apex/NBAQueueManager.getAccountPhoneNumber';
import { loadStyle } from 'lightning/platformResourceLoader';
import { publish, MessageContext } from 'lightning/messageService';
import OpportunityContextChannel from '@salesforce/messageChannel/NBA_OpportunityContext__c';
import PlusJakartaSans from '@salesforce/resourceUrl/PlusJakartaSans';

export default class NbaQueueConsolePage extends NavigationMixin(LightningElement) {
    @api debugFlow = false;
    @track _lastPublishedOppId;
    @track _lastPublishedTs;
    @wire(MessageContext) messageContext;
    @track queueItem = null;
    @track upNextItem = null;
    @track isLoading = false;
    @track showCallDispositionForm = false;
    @track showDismissForm = false;
    @track callDisposition = '';
    @track callNotes = '';
    @track dismissReason = '';
    @track currentTaskId = null;
    @track opportunityPrimaryContact = null;
    @track emailTo = '';
    @track emailSubject = '';
    @track emailBody = '';
    @track emailTemplates = [];
    @track selectedTemplateId = '';
    @track currentPhoneNumber = '';

    // Collapse state for record detail sections
    @track oppDetailsCollapsed = false;
    @track payrollDetailsCollapsed = false;
    @track nextFollowCollapsed = false;
    @track showProjectFlow = false; // deprecated: embedded host removed

    // Field sets for record details sections
    opportunityDetailsFields = [
        'Name', 'StageName',
        'CloseDate', 'Primary_Contact__c'
    ];

    opportunityPayrollFields = [
        'Payroll_Buyer_Stage__c', 'Payroll_Risk_Level__c',
        'Fed_Auth_Finish_Time__c', 'Bank_Connect_Finish__c',
        'Pay_Sched_Finish__c', 'Last_Progression_Time__c'
    ];

    opportunityNextFollowUpFields = [
        'Next_Step_Date__c', 'NextStep',
        'Future_Follow_Up_Date__c', 'Future_Follow_Up_Reason__c'
    ];

    accountFields = [
        'Name',
        'Phone',
        'Website',
        'Employee_Count__c',
        // Account action links
        'Check_Console_Link__c',
        'Admin_Link__c',
        'Reactive_Admin_Link__c'
    ];

    // Lead details fields for Lead-based NBA items
    leadDetailsFields = [
        'Company', 'Status', 'Email', 'Phone', 'Are_you__c', 'Number_of_Employees__c'
    ];

    // Account Actions (to display on Opportunity context as Account fields)
    accountActionFields = [
        'Check_Console_Link__c',
        'Admin_Link__c',
        'Reactive_Admin_Link__c'
    ];

    // Section toggles
    toggleOppDetails = () => { this.oppDetailsCollapsed = !this.oppDetailsCollapsed; }
    togglePayrollDetails = () => { this.payrollDetailsCollapsed = !this.payrollDetailsCollapsed; }
    toggleNextFollow = () => { this.nextFollowCollapsed = !this.nextFollowCollapsed; }

    // Chevron classes
    get oppChevronClass() { return this.oppDetailsCollapsed ? 'chevron' : 'chevron rotated'; }
    get payrollChevronClass() { return this.payrollDetailsCollapsed ? 'chevron' : 'chevron rotated'; }
    get nextFollowChevronClass() { return this.nextFollowCollapsed ? 'chevron' : 'chevron rotated'; }

    currentUserId = userId;
    refreshTimer = null;
    refreshInterval = 300000; // 5 minutes, same as widget

    // Adjustable layout state (two columns)
    @track leftWidth = 1; // grid fractions: left 1fr, right 1fr default
    @track rightWidth = 1;
    @track panelHeightPx = 900;
    isResizing = false;
    resizeTarget = null; // 'leftRight' | 'height'
    startX = 0;
    startY = 0;
    startWidths = null;

    get gridStyle() {
        return `grid-template-columns: ${this.leftWidth}fr ${this.rightWidth}fr; --panel-height: ${this.panelHeightPx}px;`;
    }

    startResizeLeftRight = (e) => {
        this.isResizing = true;
        this.resizeTarget = 'leftRight';
        this.startX = e.clientX;
        this.startWidths = { left: this.leftWidth, right: this.rightWidth };
        e.preventDefault();
    }

    startResizeHeight = (e) => {
        this.isResizing = true;
        this.resizeTarget = 'height';
        this.startY = e.clientY;
        this.startHeight = this.panelHeightPx;
        e.preventDefault();
    }

    handleGlobalMouseMove = (e) => {
        if (!this.isResizing) return;
        if (this.resizeTarget === 'leftRight') {
            const delta = (e.clientX - this.startX) / 150; // scale factor
            const newLeft = Math.max(0.5, this.startWidths.left + delta);
            const newRight = Math.max(0.5, this.startWidths.right - delta);
            this.leftWidth = newLeft;
            this.rightWidth = newRight;
        } else if (this.resizeTarget === 'height') {
            // Dragging down increases height; dragging up decreases
            const deltaY = (e.clientY - this.startY);
            const next = this.startHeight + deltaY;
            // Clamp between min 20px and max 1400px
            this.panelHeightPx = Math.max(20, Math.min(1400, next));
        }
    }

    handleGlobalMouseUp = () => {
        if (!this.isResizing) return;
        this.isResizing = false;
        this.resizeTarget = null;
    }

    connectedCallback() {
        // Load the Plus Jakarta Sans font to match the widget
        loadStyle(this, PlusJakartaSans + '/PlusJakartaSans.css')
            .catch(() => {})
            .finally(() => {
                this.refreshItem();
                this.startAutoRefresh();
                // Sync column heights after initial render and on resize
                setTimeout(() => this.syncColumnHeights(), 0);
                this._resizeHandler = () => this.syncColumnHeights();
                window.addEventListener('resize', this._resizeHandler);
                // Suppress unhandled Promise rejections that may bubble from framework internals
                try {
                    this._unhandledRejectionHandler = (evt) => {
                        try { console.log('Console: suppressed async rejection:', evt && (evt.reason || evt)); } catch (e) {}
                        try { evt && evt.preventDefault && evt.preventDefault(); } catch (e2) {}
                    };
                    window.addEventListener('unhandledrejection', this._unhandledRejectionHandler);
                } catch (e) {}
            });
    }

    disconnectedCallback() {
        this.stopAutoRefresh();
        if (this._resizeHandler) {
            window.removeEventListener('resize', this._resizeHandler);
            this._resizeHandler = null;
        }
        try {
            if (this._unhandledRejectionHandler) {
                window.removeEventListener('unhandledrejection', this._unhandledRejectionHandler);
                this._unhandledRejectionHandler = null;
            }
        } catch (e) {}
    }

    async refreshItem() {
        this.isLoading = true;
        try {
            const result = await getNextQueueItemWithDetails({ userId: this.currentUserId });
            this.queueItem = result?.queueItem || null;
            // Publish Opportunity context to LMS for Mogli host
            try {
                const oppId = this.queueItem?.Opportunity__c || null;
                if (oppId && oppId !== this._lastPublishedOppId) {
                    publish(this.messageContext, OpportunityContextChannel, { recordId: oppId });
                    this._lastPublishedOppId = oppId;
                    this._lastPublishedTs = Date.now();
                }
            } catch (e) {}
            // Load Up Next preview below the widget
            try {
                const upNext = await getUpNextItem({ userId: this.currentUserId, excludeQueueItemId: this.queueItem ? this.queueItem.Id : null });
                this.upNextItem = upNext && upNext.upNext ? upNext.upNext : null;
            } catch (e) {
                this.upNextItem = null;
            }
            // Deprecated: no embedded flow host
            this.showProjectFlow = false;
            // Ask the embedded widget to refresh activities if visible on Activity tab
            try {
                const widget = this.template.querySelector('c-nba-queue-widget');
                if (widget && typeof widget.loadActivities === 'function') {
                    widget.loadActivities();
                }
            } catch (e) {}
            if (this.queueItem?.Opportunity__c) {
                try {
                    this.opportunityPrimaryContact = await getOpportunityPrimaryContact({ opportunityId: this.queueItem.Opportunity__c });
                } catch (e) {
                    this.opportunityPrimaryContact = null;
                }
            } else if (this.queueItem?.Account__c) {
                try {
                    this.opportunityPrimaryContact = await getAccountPrimaryContact({ accountId: this.queueItem.Account__c });
                } catch (e) {
                    this.opportunityPrimaryContact = null;
                }
            }
            // seed email defaults (prefer Lead email when present)
            this.emailTo = this.queueItem?.Lead__r?.Email || this.opportunityPrimaryContact?.contactEmail || '';
            this.emailSubject = this.queueItem?.Subject__c || '';
            this.emailBody = '';
            // load email templates (basic list)
            try {
                this.emailTemplates = await listEmailTemplates({ searchText: '' });
            } catch (e) { this.emailTemplates = []; }
        } catch (e) {
            this.queueItem = null;
            this.upNextItem = null;
        } finally {
            this.isLoading = false;
            // Defer to ensure DOM has rendered before measuring
            setTimeout(() => this.syncColumnHeights(), 0);
        }
    }

    startAutoRefresh() {
        if (this.refreshTimer) return;
        this.refreshTimer = setInterval(() => {
            if (!this.isLoading && !this.showCallDispositionForm && !this.showDismissForm) {
                this.refreshItem().catch(() => {});
            }
        }, this.refreshInterval);
    }

    stopAutoRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = null;
        }
    }

    get hasItem() {
        return !!(this.queueItem && this.queueItem.Id);
    }

    get isOpportunity() {
        return !!(this.queueItem && this.queueItem.Opportunity__c);
    }

    get primaryRecordName() {
        if (!this.queueItem) return '';
        if (this.queueItem.Lead__c) return this.queueItem.Lead__r?.Name || '';
        return this.queueItem.Opportunity__c ? (this.queueItem.Opportunity__r?.Name || '') : (this.queueItem.Account__r?.Name || '');
    }

    handleNavigatePrimary = () => {
        if (!this.queueItem) return;
        if (this.queueItem.Lead__c) {
            this.navigateToRecord(this.queueItem.Lead__c, 'Lead');
        } else if (this.queueItem.Opportunity__c) {
            this.navigateToRecord(this.queueItem.Opportunity__c, 'Opportunity');
        } else if (this.queueItem.Account__c) {
            this.navigateToRecord(this.queueItem.Account__c, 'Account');
        }
    }

    // Phone resolution for current item (mirror widget behavior)
    getPhoneForCurrentItem() {
        if (!this.queueItem) return null;
        // Prefer Best Number
        if (this.queueItem.Best_Number_to_Call__c) return this.queueItem.Best_Number_to_Call__c;
        // Lead path
        if (this.queueItem.Lead__c && this.queueItem.Lead__r) {
            return this.queueItem.Lead__r.Phone || this.queueItem.Lead__r.MobilePhone || null;
        }
        // Opportunity path
        if (this.queueItem.Opportunity__c) {
            return (this.opportunityPrimaryContact && this.opportunityPrimaryContact.contactPhone) ? this.opportunityPrimaryContact.contactPhone : null;
        }
        // Account fallback
        return null;
    }

    launchCallWithNumber(number, recordId, recordName) {
        if (!number) return;
        let cleanedNumber = number.replace(/\D/g, '');
        if (!number.startsWith('+')) {
            if (cleanedNumber.length === 10) cleanedNumber = '1' + cleanedNumber;
            cleanedNumber = '+' + cleanedNumber;
        } else {
            cleanedNumber = number;
        }
        this.currentPhoneNumber = cleanedNumber;
        console.log('Console launchCallWithNumber resolved:', cleanedNumber, 'contextId:', recordId, 'contextName:', recordName);
        try { this.tryTalkdeskLaunch(cleanedNumber, recordId, recordName, 0); } catch (e) { console.log('Console tryTalkdeskLaunch error:', e); }
        // Fallback tel: to ensure a dial occurs
        try { this.triggerClickToCall(cleanedNumber); } catch (e) {}
    }

    triggerClickToCall(phoneNumber) {
        if (!phoneNumber) return;
        const a = document.createElement('a');
        a.href = `tel:${phoneNumber}`;
        a.style.display = 'none';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    }

    tryTalkdeskLaunch(phoneNumber, recordId, recordName, tries = 0) {
        const talkdeskButtons = document.querySelectorAll('[data-action*="dial"], [data-action*="call"], [title*="Call"], [title*="Dial"]');
        if (talkdeskButtons.length > 0) {
            talkdeskButtons[0].click();
            return;
        }
        const phoneFields = document.querySelectorAll('a[data-aura-class="uiOutputPhone"], a[data-field-type="phone"]');
        if (phoneFields.length > 0) {
            phoneFields[0].click();
            return;
        }
        if (tries < 1) {
            setTimeout(() => this.tryTalkdeskLaunch(phoneNumber, recordId, recordName, tries + 1), 300);
            return;
        }
    }

    handleAccept = async () => {
        if (!this.queueItem) return;
        this.isLoading = true;
        try {
            await acceptAction({ queueItemId: this.queueItem.Id, additionalNotes: '' });
            // Task will be created when call disposition is saved
            if (this.queueItem.Action_Type__c && this.queueItem.Action_Type__c.includes('Call')) {
                // Launch the call with resolved number
                const phone = this.getPhoneForCurrentItem();
                const contextId = this.queueItem.Opportunity__c || this.queueItem.Lead__c || this.queueItem.Account__c || null;
                const contextName = this.queueItem.Opportunity__r?.Name || this.queueItem.Lead__r?.Name || this.queueItem.Account__r?.Name || '';
                // Pre-seed current phone number for disposition form immediately
                this.currentPhoneNumber = (phone || this.queueItem?.Lead__r?.Phone || this.queueItem?.Lead__r?.MobilePhone || this.opportunityPrimaryContact?.contactPhone || '');
                if (phone) this.launchCallWithNumber(phone, contextId, contextName);
                // Show disposition form after a short delay to avoid racing the dial click
                setTimeout(() => { this.showCallDispositionForm = true; }, 700);
                // Pre-populate with Opp/Lead description if present
                if (this.queueItem.Opportunity__r && this.queueItem.Opportunity__r.Description) {
                    this.callNotes = this.queueItem.Opportunity__r.Description;
                } else if (this.queueItem.Lead__r && this.queueItem.Lead__r.Description) {
                    this.callNotes = this.queueItem.Lead__r.Description;
                } else {
                    this.callNotes = '';
                }
            } else if (this.queueItem.Action_Type__c && this.queueItem.Action_Type__c.toLowerCase().includes('email')) {
                // Stay on the item; middle panel shows inline email composer
            } else {
                await this.refreshItem();
            }
        } catch (e) {
            // swallow
        } finally {
            this.isLoading = false;
        }
    }

    handleDismiss = () => {
        // Open dismiss form to collect reason
        this.dismissReason = '';
        this.showDismissForm = true;
    }

    closeDismissForm = () => {
        this.showDismissForm = false;
        this.dismissReason = '';
    }

    handleDismissReasonChange = (event) => {
        this.dismissReason = event.target.value;
    }

    submitDismissReason = async () => {
        if (!this.queueItem) return;
        if (!this.dismissReason || !this.dismissReason.trim()) {
            return; // basic guard; UI keeps button disabled
        }
        this.isLoading = true;
        try {
            await dismissAction({ queueItemId: this.queueItem.Id, dismissalReason: this.dismissReason });
            this.showDismissForm = false;
            this.dismissReason = '';
            await this.refreshItem();
        } catch (e) {
            // swallow
        } finally {
            this.isLoading = false;
        }
    }

    handleCancelDisposition = async () => {
        if (!this.queueItem) return;
        try {
            await cancelCallDisposition({ queueItemId: this.queueItem.Id });
        } catch (e) {}
        this.showCallDispositionForm = false;
        this.currentTaskId = null;
        this.callDisposition = '';
        await this.refreshItem();
    }

    handleSaveDisposition = async () => {
        if (!this.queueItem) return;
        if (!this.callDisposition) return;
        this.isLoading = true;
        try {
            await updateCallDisposition({ queueItemId: this.queueItem.Id, disposition: this.callDisposition, callNotes: this.callNotes });
            this.showCallDispositionForm = false;
            this.callDisposition = '';
            this.callNotes = '';
            // Deprecated: embedded flow host path removed; flows launched directly from widget
            await this.refreshItem();
        } catch (e) {
            // swallow
        } finally {
            this.isLoading = false;
        }
    }

    handleFlowComplete = async () => {
        // After flow completion, refresh to get next item
        await this.refreshItem();
    }

    handleDispositionChange = (event) => {
        this.callDisposition = event.target.value;
    }

    handleNotesChange = (event) => {
        this.callNotes = event.target.value;
    }

    handleEmailToChange = (e) => { this.emailTo = e.target.value; }
    handleEmailSubjectChange = (e) => { this.emailSubject = e.target.value; }
    handleEmailBodyChange = (e) => { this.emailBody = e.target.value; }
    sendEmail = async () => {
        if (!this.queueItem) return;
        this.isLoading = true;
        try {
            if (this.selectedTemplateId) {
                const whatId = this.queueItem?.Opportunity__c || this.queueItem?.Account__c || null;
                const whoId = this.opportunityPrimaryContact?.contactId || null;
                // If we have a whoId and template, send using template
                if (whoId) {
                    await window.eval; // no-op to keep formatting stable
                    await sendQueueEmailWithTemplate({
                        queueItemId: this.queueItem.Id,
                        templateId: this.selectedTemplateId,
                        whoId: whoId,
                        whatId: whatId,
                        subjectOverride: this.emailSubject || null
                    });
                } else {
                    // Fallback to direct send if no whoId available
                    await sendQueueEmail({ queueItemId: this.queueItem.Id, toAddress: this.emailTo, subject: this.emailSubject, htmlBody: this.emailBody });
                }
            } else {
                await sendQueueEmail({ queueItemId: this.queueItem.Id, toAddress: this.emailTo, subject: this.emailSubject, htmlBody: this.emailBody });
            }
        } catch (e) {
            // swallow
        } finally {
            this.isLoading = false;
        }
    }

    handleTemplateChange = async (e) => {
        this.selectedTemplateId = e.detail?.value || e.target?.value || '';
        // We will apply the template at send time using Apex setTemplateId
    }

    navigateToRecord(recordId, objectApiName) {
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
        });
    }

    openNativeEmailComposer = () => {
        const recordId = this.queueItem?.Opportunity__c || this.queueItem?.Account__c;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: { apiName: 'Global.SendEmail' },
            state: { recordId }
        });
    }

    get callScript() {
        return this.queueItem?.Call_Script__c || '';
    }

    // Contact display helpers (mirroring widget logic)
    get shouldUseNBAQueueContact() {
        if (!this.queueItem?.Opportunity__c) {
            return true;
        }
        const stage = this.queueItem?.Opportunity__r?.StageName;
        return stage === 'New Opportunity' || stage === 'Attempted';
    }

    get displayContactPerson() {
        if (this.shouldUseNBAQueueContact) {
            return this.queueItem?.Best_Person_to_Call__r?.Name || '';
        }
        return this.opportunityPrimaryContact?.contactName || '';
    }

    get displayContactId() {
        if (this.shouldUseNBAQueueContact) {
            return this.queueItem?.Best_Person_to_Call__c || '';
        }
        return this.opportunityPrimaryContact?.contactId || '';
    }

    get displayContactEmail() {
        if (this.shouldUseNBAQueueContact) {
            return this.queueItem?.Best_Person_to_Call__r?.Email || '';
        }
        return this.opportunityPrimaryContact?.contactEmail || '';
    }

    get displayContactPhone() {
        if (this.queueItem?.Opportunity__c) {
            const stage = this.queueItem?.Opportunity__r?.StageName;
            if (stage === 'New Opportunity' || stage === 'Attempted') {
                return this.queueItem?.Best_Number_to_Call__c || this.opportunityPrimaryContact?.contactPhone || '';
            }
            return this.opportunityPrimaryContact?.contactPhone || '';
        }
        return this.queueItem?.Best_Number_to_Call__c || '';
    }

    async getAccountPhoneFallback() {
        if (!this.queueItem?.Opportunity__c && this.queueItem?.Account__c && !this.displayContactPhone) {
            try {
                const phone = await getAccountPhoneNumber({ accountId: this.queueItem.Account__c });
                return phone;
            } catch (e) { return ''; }
        }
        return '';
    }

    get dispositionOptions() {
        return [
            { label: 'Connected - DM', value: 'Connected - DM' },
            { label: 'Connected - GK', value: 'Connected - GK' },
            { label: 'Attempted - Left Voicemail', value: 'Attempted - Left Voicemail' },
            { label: 'Attempted - No Voicemail', value: 'Attempted - No Voicemail' },
            { label: 'Invalid Number', value: 'Invalid Number' },
            { label: 'Not Interested', value: 'Not Interested' }
        ];
    }

    get isSaveDisabled() {
        return this.isLoading || !this.callDisposition;
    }

    get recordPanelTitle() {
        if (!this.queueItem) return '';
        if (this.queueItem.Lead__c) return 'Lead';
        return this.queueItem.Opportunity__c ? 'Opportunity' : 'Account';
    }

    get isDismissSaveDisabled() {
        return this.isLoading || !(this.dismissReason && this.dismissReason.trim());
    }

    // Custom display: Current Payroll preference
    // Prefer NBA Queue field Current_Payroll_Provider__c, else Opportunity.Current_Payroll_Integration__c
    get currentPayrollDisplay() {
        if (!this.queueItem) return '';
        const fromQueue = this.queueItem.Current_Payroll_Provider__c;
        if (fromQueue) return fromQueue;
        return this.queueItem.Opportunity__r?.Current_Payroll_Integration__c || '';
    }

    get queueNextStepDateDisplay() {
        try {
            const d = this.queueItem?.Next_Step_Date__c;
            if (!d) return '';
            const dt = new Date(d);
            return dt.toLocaleDateString();
        } catch (e) { return ''; }
    }

    // Up Next helpers
    handleUpNextRecordClick = () => {
        if (!this.upNextItem) return;
        const recordId = this.upNextItem.Opportunity__c || this.upNextItem.Account__c;
        const objectApiName = this.upNextItem.Opportunity__c ? 'Opportunity' : 'Account';
        if (!recordId) return;
        this.navigateToRecord(recordId, objectApiName);
    }

    syncColumnHeights() {
        try {
            const left = this.template.querySelector('.left');
            const rightPanel = this.template.querySelector('.right .panel');
            if (!left || !rightPanel) return;
            const leftHeight = left.offsetHeight;
            if (leftHeight && leftHeight > 0) {
                rightPanel.style.height = leftHeight + 'px';
            }
        } catch (e) {
            // no-op
        }
    }

    // Up Next display helpers styled like the widget
    get upNextActionText() {
        if (!this.upNextItem) return '';
        const objectType = this.upNextItem.Lead__c ? 'Lead' : (this.upNextItem.Opportunity__c ? 'Opportunity' : 'Account');
        const typeRaw = this.upNextItem.Action_Type__c || '';
        let actionShort = 'Action';
        const t = typeRaw.toLowerCase();
        if (t.includes('email')) actionShort = 'Email';
        else if (t.includes('call')) actionShort = 'Call';
        else actionShort = typeRaw.replace(/_/g, ' ');
        return `${objectType} ${actionShort} for`;
    }

    get upNextRecordName() {
        if (!this.upNextItem) return '';
        if (this.upNextItem.Lead__c) return this.upNextItem.Lead__r?.Name || '';
        return this.upNextItem.Opportunity__c ? (this.upNextItem.Opportunity__r?.Name || '') : (this.upNextItem.Account__r?.Name || '');
    }
}

