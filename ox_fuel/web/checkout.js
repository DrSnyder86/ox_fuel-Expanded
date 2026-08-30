(() => {
    const meter = document.getElementById('fuel-meter');
    const terminal = document.getElementById('ev-terminal');
    const pumpLogo = document.getElementById('pump-logo');
    const pumpLogoImage = document.getElementById('pump-logo-image');
    const panel = document.getElementById('checkout-panel');
    const title = document.getElementById('checkout-title');
    const primaryLabel = document.getElementById('checkout-primary-label');
    const paymentLabel = document.getElementById('checkout-payment-label');
    const primaryOptions = document.getElementById('checkout-primary-options');
    const paymentOptions = document.getElementById('checkout-payment-options');
    const summary = document.getElementById('checkout-summary');
    const confirm = document.getElementById('checkout-confirm');
    const cancel = document.getElementById('checkout-cancel');
    const local = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';
    const logoSources = {
        prop_gas_pump_1a: 'logos/ui/prop_gas_pump_1a.png',
        prop_gas_pump_1b: 'logos/ui/prop_gas_pump_1b.png',
        prop_gas_pump_1c: 'logos/ui/prop_gas_pump_1c.png',
        prop_gas_pump_1d: 'logos/ui/prop_gas_pump_1d.png',
        prop_gas_pump_old2: 'logos/ui/prop_gas_pump_old2.png',
        prop_gas_pump_old3: 'logos/ui/prop_gas_pump_old3.png',
        prop_vintage_pump: 'logos/ui/prop_vintage_pump.png',
    };
    const svgNamespace = 'http://www.w3.org/2000/svg';
    const electricOptionIcons = {
        'primary:standard': [
            ['rect', { width: '18', height: '10', x: '2', y: '7', rx: '2' }],
            ['path', { d: 'M22 11v2M11 9l-2 3h3l-2 3' }],
        ],
        'primary:rapid': [
            ['path', { d: 'M4 14a1 1 0 0 1-.8-1.6l9-11a.5.5 0 0 1 .9.4L11.4 8a1 1 0 0 0 1 1H20a1 1 0 0 1 .8 1.6l-9 11a.5.5 0 0 1-.9-.4l1.7-6.2a1 1 0 0 0-1-1Z' }],
        ],
        'primary:portable': [
            ['rect', { width: '16', height: '18', x: '4', y: '3', rx: '2' }],
            ['path', { d: 'M9 1h6M10 8l-2 4h4l-2 4' }],
        ],
        'payment:cash': [
            ['rect', { width: '20', height: '12', x: '2', y: '6', rx: '2' }],
            ['circle', { cx: '12', cy: '12', r: '2' }],
            ['path', { d: 'M6 12h.01M18 12h.01' }],
        ],
        'payment:bank': [
            ['path', { d: 'M3 22h18M6 18v-7M10 18v-7M14 18v-7M18 18v-7M12 2 2 7h20Z' }],
        ],
    };

    let state;

    function findOption(options, id) {
        return options.find((option) => option.id === id);
    }

    function createOptionIcon(group, optionId) {
        if (state?.checkoutType !== 'electric') return;

        const definitions = electricOptionIcons[`${group}:${optionId}`];

        if (!definitions) return;

        const icon = document.createElementNS(svgNamespace, 'svg');
        icon.classList.add('checkout-option-icon');
        icon.setAttribute('viewBox', '0 0 24 24');
        icon.setAttribute('aria-hidden', 'true');

        for (const [tagName, attributes] of definitions) {
            const element = document.createElementNS(svgNamespace, tagName);

            for (const [name, value] of Object.entries(attributes)) element.setAttribute(name, value);

            icon.appendChild(element);
        }

        return icon;
    }

    function createOption(option, group, selectedId) {
        const button = document.createElement('button');
        const name = document.createElement('span');
        const meta = document.createElement('span');
        const badge = option.badge ? document.createElement('strong') : null;
        const icon = createOptionIcon(group, option.id);

        button.type = 'button';
        button.className = 'checkout-option';
        button.dataset.group = group;
        button.dataset.optionId = option.id;
        button.setAttribute('role', 'radio');
        button.setAttribute('aria-checked', String(option.id === selectedId));
        button.classList.toggle('is-selected', option.id === selectedId);
        name.className = 'checkout-option-name';
        name.textContent = option.label;
        meta.className = 'checkout-option-meta';
        meta.textContent = option.meta || option.shortLabel || '';

        if (badge) {
            badge.className = 'checkout-option-badge';
            badge.textContent = option.badge;
            button.classList.add('has-badge');
            button.append(badge, name, meta);
        } else {
            if (icon) button.appendChild(icon);
            button.append(name, meta);
        }
        button.addEventListener('click', () => selectOption(group, option.id));

        return button;
    }

    function renderOptions(container, options, group, selectedId) {
        const fragment = document.createDocumentFragment();

        for (const option of options) fragment.appendChild(createOption(option, group, selectedId));

        container.replaceChildren(fragment);
    }

    function updateSelection() {
        if (!state) return;

        const primary = findOption(state.primaryOptions, state.primaryId);
        const selectedPayment = findOption(state.paymentOptions, state.paymentId);
        const details = [primary?.meta, primary?.benefit, selectedPayment?.meta].filter(Boolean);

        summary.textContent = details.join(' \u00b7 ');
        confirm.disabled = !primary || !selectedPayment || state.submitting;

        for (const button of panel.querySelectorAll('.checkout-option')) {
            const selectedId = button.dataset.group === 'primary' ? state.primaryId : state.paymentId;
            const selected = button.dataset.optionId === selectedId;
            button.classList.toggle('is-selected', selected);
            button.setAttribute('aria-checked', String(selected));
        }
    }

    function selectOption(group, id) {
        if (!state || state.submitting) return;

        if (group === 'primary') state.primaryId = id;
        if (group === 'payment') state.paymentId = id;
        updateSelection();
    }

    function applyPresentation(data) {
        const electric = data.checkoutType === 'electric';
        const theme = data.theme === 'vintage' ? 'vintage' : 'modern';
        const logoSource = !electric && logoSources[data.logo];

        meter.style.setProperty('--brand-accent', data.accent || (electric ? '#20bff5' : '#56c596'));
        meter.dataset.theme = theme;
        meter.dataset.variant = data.variant || (electric ? 'charge-modern' : `${theme}-generic`);
        meter.dataset.brand = logoSource ? data.logo : 'none';
        meter.classList.toggle('is-electric', electric);
        terminal.hidden = !electric;
        pumpLogo.hidden = !logoSource;

        if (logoSource) {
            pumpLogoImage.src = logoSource;
            pumpLogoImage.alt = `${data.brand || 'Fuel pump'} logo`;
            pumpLogoImage.dataset.logo = data.logo;
        }
    }

    function show(data) {
        state = {
            checkoutType: data.checkoutType,
            primaryOptions: Array.isArray(data.primaryOptions) ? data.primaryOptions : [],
            paymentOptions: Array.isArray(data.paymentOptions) ? data.paymentOptions : [],
            primaryId: data.primaryId,
            paymentId: data.paymentId,
            submitting: false,
        };

        applyPresentation(data);
        title.textContent = data.title || 'Options';
        primaryLabel.textContent = data.primaryLabel || 'Type';
        paymentLabel.textContent = data.paymentLabel || 'Payment';
        confirm.textContent = data.confirmLabel || 'Confirm';
        cancel.setAttribute('aria-label', data.cancelLabel || 'Close');
        cancel.title = data.cancelLabel || 'Close';
        renderOptions(primaryOptions, state.primaryOptions, 'primary', state.primaryId);
        renderOptions(paymentOptions, state.paymentOptions, 'payment', state.paymentId);
        panel.hidden = false;
        meter.classList.add('is-visible', 'is-checkout');
        meter.setAttribute('aria-hidden', 'false');
        updateSelection();
        requestAnimationFrame(() => panel.querySelector('.checkout-option.is-selected')?.focus());
    }

    function close() {
        state = null;
        panel.hidden = true;
        meter.classList.remove('is-checkout');
    }

    async function post(eventName, payload = {}) {
        if (local || typeof GetParentResourceName !== 'function') return { ok: true };

        const response = await fetch(`https://${GetParentResourceName()}/${eventName}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload),
        });

        return response.json();
    }

    async function submit() {
        if (!state || state.submitting || confirm.disabled) return;

        const active = state;
        active.submitting = true;
        updateSelection();
        await post('checkoutSubmit', {
            primaryId: active.primaryId,
            paymentId: active.paymentId,
        });

        if (state === active) close();
    }

    async function dismiss() {
        if (!state || state.submitting) return;

        const active = state;
        active.submitting = true;
        await post('checkoutCancel');

        if (state === active) close();
    }

    confirm.addEventListener('click', submit);
    cancel.addEventListener('click', dismiss);
    panel.addEventListener('keydown', (event) => {
        if (!state) return;

        if (event.key === 'Escape') {
            event.preventDefault();
            dismiss();
            return;
        }

        if (event.key === 'Enter' && event.target !== confirm) {
            event.preventDefault();
            submit();
            return;
        }

        if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;

        const current = event.target.closest('.checkout-option');

        if (!current) return;

        const buttons = [...panel.querySelectorAll(`.checkout-option[data-group="${current.dataset.group}"]`)];
        const direction = event.key === 'ArrowRight' ? 1 : -1;
        const next = buttons[(buttons.indexOf(current) + direction + buttons.length) % buttons.length];

        event.preventDefault();
        next.focus();
        next.click();
    });

    window.addEventListener('message', (event) => {
        const data = event.data || {};

        if (data.action === 'options') {
            show(data);
            return;
        }

        if (data.action === 'closeOptions' || data.action === 'hide') close();
    });

    const preview = new URLSearchParams(window.location.search).get('preview');

    if (local && preview?.endsWith('-options')) {
        const electric = preview.startsWith('charging');
		const portable = preview === 'charging-portable-options';

        show({
            checkoutType: electric ? 'electric' : 'fuel',
			title: portable ? 'Portable charger purchase' : (electric ? 'Charging options' : 'Pump options'),
			primaryLabel: portable ? 'Portable EV charger' : (electric ? 'Charging speed' : 'Fuel grade'),
            paymentLabel: 'Payment method',
            confirmLabel: 'Confirm',
            cancelLabel: 'Close',
			primaryId: portable ? 'portable' : (electric ? 'standard' : 'regular'),
            paymentId: 'cash',
			primaryOptions: portable
				? [
					{ id: 'portable', label: 'Portable EV charger', meta: '$2,500.00', benefit: '12.0 kWh' },
				]
				: electric
                ? [
                    { id: 'standard', label: 'Standard', meta: '$0.52/kWh', benefit: '150 kW' },
                    { id: 'rapid', label: 'Rapid', meta: '$0.72/kWh', benefit: '250 kW' },
                ]
                : [
                    { id: 'regular', label: 'Regular', shortLabel: 'REG', badge: '87', meta: '$5.82/GAL' },
                    { id: 'premium', label: 'Premium', shortLabel: 'PREM', badge: '93', meta: '$8.45/GAL', benefit: '10% less consumption' },
                ],
            paymentOptions: [
                { id: 'cash', label: 'Cash', meta: '$1,250 available' },
                { id: 'bank', label: 'Bank', meta: '$18,420 available' },
            ],
            theme: electric ? 'modern' : 'vintage',
            variant: electric ? 'charge-modern' : 'globe-vintage',
            logo: electric ? 'electric_charger' : 'prop_vintage_pump',
            accent: electric ? '#19b9ff' : '#d9584f',
        });
    }
})();
