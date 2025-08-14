import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import userId from '@salesforce/user/Id';
import getNextQueueItemWithDetails from '@salesforce/apex/NBAQueueManager.getNextQueueItemWithDetails';
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
import PlusJakartaSans from '@salesforce/resourceUrl/PlusJakartaSans';

export default class NbaQueueConsolePage extends NavigationMixin(LightningElement) {
    @track queueItem = null;
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

    // Curated field sets for inline record form
    opportunityFields = [
        // Row 1
        'Name',
        'StageName',
        // Row 2
        'CloseDate',
        'Primary_Contact__c',
        // Row 3
        'Account__Time_Zone__c',
        'Source__c',
        // Row 4
        'Current_Payroll_Provider__c',
        // Row 5
        'Payroll_Buyer_Stage__c',
        'Last_Payroll_Activity_Time__c',
        // Row 6
        'Bank_Connect_Finish__c',
        'Check_info_Needed__c'
    ];

    accountFields = [
        'Name',
        'Phone',
        'Website',
        'Employee_Count__c'
    ];

    currentUserId = userId;
    refreshTimer = null;
    refreshInterval = 30000; // 30s, same as widget

    // Adjustable layout state
    @track leftWidth = 1; // grid fractions: left 1fr, middle 1fr, right 2fr default
    @track middleWidth = 1;
    @track rightWidth = 2;
    @track panelHeightPx = 900;
    isResizing = false;
    resizeTarget = null; // 'leftMiddle' | 'middleRight' | 'height'
    startX = 0;
    startY = 0;
    startWidths = null;

    get gridStyle() {
        return `grid-template-columns: ${this.leftWidth}fr ${this.middleWidth}fr ${this.rightWidth}fr; --panel-height: ${this.panelHeightPx}px;`;
    }

    startResizeLeftMiddle = (e) => {
        this.isResizing = true;
        this.resizeTarget = 'leftMiddle';
        this.startX = e.clientX;
        this.startWidths = { left: this.leftWidth, middle: this.middleWidth };
        e.preventDefault();
    }

    startResizeMiddleRight = (e) => {
        this.isResizing = true;
        this.resizeTarget = 'middleRight';
        this.startX = e.clientX;
        this.startWidths = { middle: this.middleWidth, right: this.rightWidth };
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
        if (this.resizeTarget === 'leftMiddle') {
            const delta = (e.clientX - this.startX) / 150; // scale factor
            const newLeft = Math.max(0.5, this.startWidths.left + delta);
            const newMiddle = Math.max(0.5, this.startWidths.middle - delta);
            this.leftWidth = newLeft;
            this.middleWidth = newMiddle;
        } else if (this.resizeTarget === 'middleRight') {
            const delta = (e.clientX - this.startX) / 150;
            const newMiddle = Math.max(0.5, this.startWidths.middle + delta);
            const newRight = Math.max(1, this.startWidths.right - delta);
            this.middleWidth = newMiddle;
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
            });
    }

    disconnectedCallback() {
        this.stopAutoRefresh();
    }

    async refreshItem() {
        this.isLoading = true;
        try {
            const result = await getNextQueueItemWithDetails({ userId: this.currentUserId });
            this.queueItem = result?.queueItem || null;
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
            // seed email defaults
            this.emailTo = this.opportunityPrimaryContact?.contactEmail || '';
            this.emailSubject = this.queueItem?.Subject__c || '';
            this.emailBody = '';
            // load email templates (basic list)
            try {
                this.emailTemplates = await listEmailTemplates({ searchText: '' });
            } catch (e) { this.emailTemplates = []; }
        } catch (e) {
            this.queueItem = null;
        } finally {
            this.isLoading = false;
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
        return this.queueItem.Opportunity__c ? (this.queueItem.Opportunity__r?.Name || '') : (this.queueItem.Account__r?.Name || '');
    }

    handleNavigatePrimary = () => {
        if (!this.queueItem) return;
        if (this.queueItem.Opportunity__c) {
            this.navigateToRecord(this.queueItem.Opportunity__c, 'Opportunity');
        } else if (this.queueItem.Account__c) {
            this.navigateToRecord(this.queueItem.Account__c, 'Account');
        }
    }

    handleAccept = async () => {
        if (!this.queueItem) return;
        this.isLoading = true;
        try {
            const taskId = await acceptAction({ queueItemId: this.queueItem.Id, additionalNotes: '' });
            this.currentTaskId = taskId;
            if (this.queueItem.Action_Type__c && this.queueItem.Action_Type__c.includes('Call')) {
                this.showCallDispositionForm = true;
                // Pre-populate with Opp description if present
                if (this.queueItem.Opportunity__r && this.queueItem.Opportunity__r.Description) {
                    this.callNotes = this.queueItem.Opportunity__r.Description;
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
        if (!this.currentTaskId || !this.queueItem) return;
        if (!this.callDisposition) return;
        this.isLoading = true;
        try {
            await updateCallDisposition({ taskId: this.currentTaskId, queueItemId: this.queueItem.Id, disposition: this.callDisposition, callNotes: this.callNotes });
            this.showCallDispositionForm = false;
            this.currentTaskId = null;
            this.callDisposition = '';
            this.callNotes = '';
            await this.refreshItem();
        } catch (e) {
            // swallow
        } finally {
            this.isLoading = false;
        }
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

    get isEmailAction() {
        const type = this.queueItem?.Action_Type__c || '';
        return type.toLowerCase().includes('email');
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
        return this.queueItem.Opportunity__c ? 'Opportunity' : 'Account';
    }

    get isDismissSaveDisabled() {
        return this.isLoading || !(this.dismissReason && this.dismissReason.trim());
    }
}

