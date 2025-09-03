import { LightningElement, api } from 'lwc';

export default class EmbeddedFlowHost extends LightningElement {
    @api flowApiName;
    @api recordId;
    @api queueItemId;
    @api debug = false;
    statusText = '';

    renderedCallback() {
        const flow = this.template.querySelector('lightning-flow');
        if (!flow || !this.flowApiName) return;
        try {
            if (this.debug) this.statusText = `Starting flow ${this.flowApiName}...`;
            const inputs = [];
            if (this.recordId) inputs.push({ name: 'recordId', type: 'String', value: this.recordId });
            if (this.queueItemId) inputs.push({ name: 'queueItemId', type: 'String', value: this.queueItemId });
            flow.startFlow(this.flowApiName, inputs);
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Failed to start flow:', e);
            if (this.debug) this.statusText = `Failed to start: ${e}`;
        }
    }

    handleStatusChange(event) {
        const s = event.detail && event.detail.status ? event.detail.status : null;
        if (this.debug) this.statusText = `Status: ${s}`;
        // bubble status for container layout adjustments
        this.dispatchEvent(new CustomEvent('flowstatus', { detail: { status: s }, bubbles: true, composed: true }));
        if (s === 'FINISHED' || s === 'FINISHED_SCREEN' || s === 'PAUSED') {
            this.dispatchEvent(new CustomEvent('flowcomplete', {
                detail: { status: s, queueItemId: this.queueItemId }
            }));
        }
    }
}


