const meter = document.getElementById('fuel-meter');
const status = document.getElementById('meter-status');
const statusIcons = {
    fuel: document.getElementById('status-fuel'),
    complete: document.getElementById('status-complete'),
    stopped: document.getElementById('status-stopped'),
};
const phase = document.getElementById('meter-phase');
const choice = document.getElementById('meter-choice');
const pumpLogo = document.getElementById('pump-logo');
const pumpLogoImage = document.getElementById('pump-logo-image');
const primaryLabel = document.getElementById('primary-label');
const primaryValue = document.getElementById('primary-value');
const secondaryLabel = document.getElementById('secondary-label');
const secondaryValue = document.getElementById('secondary-value');
const tankLevelLabel = document.getElementById('tank-level-label');
const tankLevelValue = document.getElementById('tank-level-value');

const clamp = (value, min, max) => Math.min(Math.max(Number(value) || 0, min), max);
const segmentNames = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
const activeSegments = {
    0: ['a', 'b', 'c', 'd', 'e', 'f'],
    1: ['b', 'c'],
    2: ['a', 'b', 'd', 'e', 'g'],
    3: ['a', 'b', 'c', 'd', 'g'],
    4: ['b', 'c', 'f', 'g'],
    5: ['a', 'c', 'd', 'f', 'g'],
    6: ['a', 'c', 'd', 'e', 'f', 'g'],
    7: ['a', 'b', 'c'],
    8: ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
    9: ['a', 'b', 'c', 'd', 'f', 'g'],
};
const logoSources = {
    prop_gas_pump_1a: 'logos/ui/prop_gas_pump_1a.png',
    prop_gas_pump_1b: 'logos/ui/prop_gas_pump_1b.png',
    prop_gas_pump_1c: 'logos/ui/prop_gas_pump_1c.png',
    prop_gas_pump_1d: 'logos/ui/prop_gas_pump_1d.png',
    prop_gas_pump_old2: 'logos/ui/prop_gas_pump_old2.png',
    prop_gas_pump_old3: 'logos/ui/prop_gas_pump_old3.png',
    prop_vintage_pump: 'logos/ui/prop_vintage_pump.png',
	electric_charger: 'logos/ui/electric_charger.png',
};
const supportedVariants = new Set([
    'ron-modern',
    'globe-modern',
    'ltd-modern',
    'xero-modern',
    'globe-vintage',
    'ltd-vintage',
    'xero-vintage',
	'charge-modern',
]);
const supportedStates = new Set(['ready', 'fueling', 'complete', 'stopped']);

function settleValue(container, formatted) {
    const changed = container.dataset.value !== undefined && container.dataset.value !== formatted;
    container.dataset.value = formatted;

    if (!changed) return;

    container.classList.remove('is-changing');
    void container.offsetWidth;
    container.classList.add('is-changing');
}

function renderSegments(container, value, decimals, ariaSuffix = '') {
    const formatted = Math.max(Number(value) || 0, 0).toFixed(decimals);
    const fragment = document.createDocumentFragment();

    for (const character of formatted) {
        if (character === '.') {
            const dot = document.createElement('span');
            dot.className = 'segment-dot';
            fragment.appendChild(dot);
            continue;
        }

        const digit = document.createElement('span');
        digit.className = 'segment-digit';
        digit.setAttribute('aria-hidden', 'true');

        for (const segmentName of segmentNames) {
            const segment = document.createElement('span');
            segment.className = `segment segment-${segmentName}`;

            if (activeSegments[character]?.includes(segmentName)) {
                segment.classList.add('is-on');
            }

            digit.appendChild(segment);
        }

        fragment.appendChild(digit);
    }

    container.replaceChildren(fragment);
    container.setAttribute('aria-label', `${formatted}${ariaSuffix}`);
    container.classList.remove('is-flip');
    container.classList.toggle('is-compact', formatted.length > 6);
    settleValue(container, formatted);
}

function renderFlipValue(container, value, decimals, ariaSuffix = '') {
    const formatted = Math.max(Number(value) || 0, 0).toFixed(decimals);
    const fragment = document.createDocumentFragment();

    for (const character of formatted) {
        const element = document.createElement('span');
        element.className = character === '.' ? 'flip-dot' : 'flip-character';
        element.textContent = character;
        element.setAttribute('aria-hidden', 'true');
        fragment.appendChild(element);
    }

    container.replaceChildren(fragment);
    container.setAttribute('aria-label', `${formatted}${ariaSuffix}`);
    container.classList.add('is-flip');
    container.classList.toggle('is-compact', formatted.length > 6);
    settleValue(container, formatted);
}

function renderValue(container, value, decimals, ariaSuffix, theme) {
    if (theme === 'vintage') {
        renderFlipValue(container, value, decimals, ariaSuffix);
        return;
    }

    renderSegments(container, value, decimals, ariaSuffix);
}

function updateMeter(data) {
    const rawTankPercent = Number(data.tankPercent ?? data.fuel);
    const hasTankLevel = Number.isFinite(rawTankPercent);
    const tankPercent = hasTankLevel ? clamp(rawTankPercent, 0, 100) : 0;
    const addedVolume = Math.max(Number(data.addedVolume) || 0, 0);
    const canRemainingVolume = Math.max(Number(data.canRemainingVolume) || 0, 0);
    const currency = typeof data.currency === 'string' ? data.currency : '$';
    const isElectric = data.unit === 'kilowatt-hours' || data.mode === 'charging';
    const unitLabel = data.unitLabel || (isElectric ? 'kWh' : (data.unit === 'liters' ? 'Liters' : 'Gallons'));
    const unitShort = isElectric ? 'KWH' : (data.unit === 'liters' ? 'L' : 'GAL');
    const unitPrice = Math.max(Number(data.unitPrice) || 0, 0);
    const volumeDecimals = isElectric || data.unit === 'liters' ? 2 : 3;
    const isPump = data.mode !== 'can';
    const theme = data.theme === 'vintage' ? 'vintage' : 'modern';
    const variant = supportedVariants.has(data.variant) ? data.variant : `${theme}-generic`;
    const brand = typeof data.brand === 'string' ? data.brand : '';
    const logo = typeof data.logo === 'string' && data.logo ? data.logo : 'none';
    const meterState = supportedStates.has(data.state)
        ? data.state
        : (data.completed === true ? 'complete' : 'fueling');
    const premiumSelected = String(data.gradeShortLabel || '').toUpperCase() === 'PREM';
    const levelLabel = data.levelLabel || (data.mode === 'can-transaction' ? 'Can' : 'Tank');

    meter.style.setProperty('--brand-accent', data.accent || '#56c596');
    meter.dataset.theme = theme;
    meter.dataset.variant = variant;
    meter.dataset.brand = brand ? logo : 'none';
    meter.dataset.state = meterState;
    meter.dataset.grade = premiumSelected ? 'premium' : 'regular';

    const statusLabel = data.label || (isPump ? 'Fueling' : 'Jerry Can');
    const statusIcon = meterState === 'complete' ? 'complete' : (meterState === 'stopped' ? 'stopped' : 'fuel');
    const choiceParts = [data.gradeShortLabel, data.paymentShortLabel].filter(Boolean);

    status.dataset.state = meterState;
    status.setAttribute('aria-label', statusLabel);

    for (const [iconName, icon] of Object.entries(statusIcons)) {
        icon.hidden = iconName !== statusIcon;
    }

    phase.textContent = data.phaseLabel || `${currency}${unitPrice.toFixed(2)}/${unitShort}`;
    phase.classList.toggle('is-choice', Boolean(data.phaseLabel));
    choice.textContent = data.phaseLabel ? '' : choiceParts.join(' \u00b7 ');
    choice.hidden = !choice.textContent;

    tankLevelLabel.textContent = levelLabel;
    tankLevelValue.textContent = hasTankLevel ? `${tankPercent.toFixed(0)}%` : '--%';
    tankLevelValue.classList.toggle('is-unavailable', !hasTankLevel);
    tankLevelValue.setAttribute('aria-label', hasTankLevel ? `${levelLabel} level ${tankPercent.toFixed(0)} percent` : `${levelLabel} level unavailable`);

    const logoSource = brand ? logoSources[logo] : null;
    pumpLogo.hidden = !logoSource;

    if (logoSource && pumpLogoImage.dataset.logo !== logo) {
        pumpLogoImage.src = logoSource;
        pumpLogoImage.alt = `${brand} logo`;
        pumpLogoImage.dataset.logo = logo;
    } else if (!logoSource) {
        pumpLogoImage.removeAttribute('src');
        pumpLogoImage.alt = '';
        pumpLogoImage.dataset.logo = '';
    }

    if (isPump) {
        primaryLabel.textContent = data.saleLabel || `Sale ${currency}`;
        secondaryLabel.textContent = unitLabel;
        renderValue(primaryValue, data.cost, 2, ` ${currency}`, theme);
        renderValue(secondaryValue, addedVolume, volumeDecimals, ` ${unitLabel}`, theme);
    } else {
        primaryLabel.textContent = data.canLabel || 'Can left';
        secondaryLabel.textContent = data.addedLabel || 'Added';
        renderValue(primaryValue, canRemainingVolume, volumeDecimals, ` ${unitLabel}`, theme);
        renderValue(secondaryValue, addedVolume, volumeDecimals, ` ${unitLabel}`, theme);
    }

    meter.classList.toggle('is-low', hasTankLevel && tankPercent < 15);
    meter.classList.toggle('is-mid', hasTankLevel && tankPercent >= 15 && tankPercent < 35);
}

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'show') {
        meter.classList.remove('is-complete');
        updateMeter(data);
        meter.classList.add('is-visible');
        meter.setAttribute('aria-hidden', 'false');
        return;
    }

    if (data.action === 'update') {
        updateMeter(data);
        return;
    }

    if (data.action === 'finish') {
        updateMeter(data);
        meter.classList.toggle('is-complete', data.completed === true);
        return;
    }

    if (data.action === 'hide') {
        meter.classList.remove('is-visible', 'is-complete');
        meter.setAttribute('aria-hidden', 'true');
    }
});

const requestedPreview = new URLSearchParams(window.location.search).get('preview');
const isLocalPreview = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';
const previewMode = requestedPreview || (isLocalPreview ? 'pump' : null);
const previewProfiles = {
    pump: { theme: 'modern', variant: 'ron-modern', brand: 'RON', logo: 'prop_gas_pump_1a', accent: '#ef8b32' },
    vintage: { theme: 'vintage', variant: 'globe-vintage', brand: 'GLOBE OIL', logo: 'prop_vintage_pump', accent: '#d9584f' },
    'ron-modern': { theme: 'modern', variant: 'ron-modern', brand: 'RON', logo: 'prop_gas_pump_1a', accent: '#ef8b32' },
    'globe-modern': { theme: 'modern', variant: 'globe-modern', brand: 'GLOBE OIL', logo: 'prop_gas_pump_1b', accent: '#d9584f' },
    'ltd-modern': { theme: 'modern', variant: 'ltd-modern', brand: 'LTD', logo: 'prop_gas_pump_1c', accent: '#d94f4f' },
    'xero-modern': { theme: 'modern', variant: 'xero-modern', brand: 'XERO', logo: 'prop_gas_pump_1d', accent: '#47c4c7' },
    'globe-vintage': { theme: 'vintage', variant: 'globe-vintage', brand: 'GLOBE OIL', logo: 'prop_vintage_pump', accent: '#d9584f' },
    'ltd-vintage': { theme: 'vintage', variant: 'ltd-vintage', brand: 'LTD', logo: 'prop_gas_pump_old3', accent: '#d94f4f' },
    'xero-vintage': { theme: 'vintage', variant: 'xero-vintage', brand: 'XERO', logo: 'prop_gas_pump_old2', accent: '#47c4c7' },
    'can-refill': { theme: 'modern', variant: 'xero-modern', brand: 'XERO', logo: 'prop_gas_pump_1d', accent: '#47c4c7' },
	charging: { theme: 'modern', variant: 'charge-modern', brand: 'SENTINEL EV CHARGING', logo: 'electric_charger', accent: '#19b9ff' },
};

if (isLocalPreview) {
    document.body.classList.add('local-preview');
}

const previewProfile = previewProfiles[previewMode];

if (previewProfile || previewMode === 'can') {
    const isCanUse = previewMode === 'can';
    const isCanRefill = previewMode === 'can-refill';
	const isCharging = previewMode === 'charging';
    const isPump = !isCanUse;

    updateMeter({
		mode: isCanRefill ? 'can-transaction' : (isCharging ? 'charging' : (isPump ? 'pump' : 'can')),
		label: isCanRefill ? 'Filling Can' : (isCharging ? 'Charging' : (isPump ? 'Fueling' : 'Jerry Can')),
        tankPercent: 63,
        state: 'fueling',
        addedVolume: 4.3,
        cost: 24.94,
        canRemainingVolume: 3.6,
        currency: '$',
		unit: isCharging ? 'kilowatt-hours' : 'gallons',
		unitLabel: isCharging ? 'kWh' : 'Gallons',
		unitPrice: isCharging ? 0.52 : (isPump ? 5.82 : 0),
        saleLabel: 'Sale $',
        canLabel: 'Can left',
        addedLabel: 'Added',
        theme: previewProfile?.theme || 'modern',
        variant: previewProfile?.variant || '',
        brand: previewProfile?.brand || '',
        logo: previewProfile?.logo || '',
        accent: previewProfile?.accent || '#56c596',
		gradeShortLabel: isCharging ? 'STD' : 'PREM',
        paymentShortLabel: 'BANK',
    });
    meter.classList.add('is-visible');
    meter.setAttribute('aria-hidden', 'false');
}
