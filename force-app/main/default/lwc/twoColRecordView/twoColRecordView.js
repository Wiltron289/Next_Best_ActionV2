import { LightningElement, api } from 'lwc';

export default class TwoColRecordView extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api fields = [];

    get fieldPairs() {
        const out = [];
        const list = Array.isArray(this.fields) ? this.fields : [];
        for (let i = 0; i < list.length; i += 2) {
            const left = list[i] || null;
            const right = list[i + 1] || null;
            out.push({ key: `${i}-${left || 'x'}-${right || 'x'}`, left, right });
        }
        return out;
    }
}


