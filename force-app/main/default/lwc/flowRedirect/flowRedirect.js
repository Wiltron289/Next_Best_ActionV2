import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class FlowRedirect extends NavigationMixin(LightningElement) {
    @api navItemApiName = 'Next_Best_Action';
    @api targetUrl; // Optional: override URL

    connectedCallback() {
        // Navigate after the screen renders to avoid interrupting Flow finish
        setTimeout(() => {
            try {
                const urlParams = new URLSearchParams(window.location.search || '');
                const retParam = urlParams.get('retURL') || urlParams.get('returnUrl');

                if (this.targetUrl && this.targetUrl.trim() !== '') {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__webPage',
                        attributes: { url: this.targetUrl }
                    });
                } else if (retParam && retParam.trim() !== '') {
                    // Use retURL from the page URL if provided
                    const decoded = decodeURIComponent(retParam);
                    this[NavigationMixin.Navigate]({
                        type: 'standard__webPage',
                        attributes: { url: decoded }
                    });
                } else if (this.navItemApiName && this.navItemApiName.trim() !== '') {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__navItemPage',
                        attributes: { apiName: this.navItemApiName }
                    });
                } else {
                    // Final fallback: NBA app tab by URL
                    this[NavigationMixin.Navigate]({
                        type: 'standard__webPage',
                        attributes: { url: '/lightning/n/Next_Best_Action' }
                    });
                }
            } catch (e) {
                // Swallow errors to avoid blocking Flow completion
                // eslint-disable-next-line no-console
                console.warn('FlowRedirect navigation failed:', e);
                this.fallbackRedirect();
            }
            // Hard fallback in case navigation doesn't take
            setTimeout(() => {
                this.fallbackRedirect();
            }, 300);
        }, 0);
    }

    fallbackRedirect() {
        try {
            const dest = (this.targetUrl && this.targetUrl.trim())
                ? this.targetUrl.trim()
                : (this.navItemApiName && this.navItemApiName.trim()
                    ? `/lightning/n/${this.navItemApiName.trim()}`
                    : '/lightning/n/Next_Best_Action');
            if (dest && window.location && window.location.assign) {
                window.location.assign(dest);
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('FlowRedirect hard fallback failed:', e);
        }
    }
}


