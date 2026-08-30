(() => {
    const meter = document.getElementById('fuel-meter');
    const terminal = document.getElementById('ev-terminal');
	const portableTerminal = document.getElementById('portable-terminal');
	const portableStatus = document.getElementById('portable-status');
	const portablePackFill = document.getElementById('portable-pack-fill');
	const portablePackValue = document.getElementById('portable-pack-value');
	const portableVehicleValue = document.getElementById('portable-vehicle-value');
	const portableEnergyValue = document.getElementById('portable-energy-value');
	const portableTimeValue = document.getElementById('portable-time-value');
    const logo = document.getElementById('ev-logo-image');
    const brand = document.getElementById('ev-brand-name');
    const clock = document.getElementById('ev-clock');
    const status = document.getElementById('ev-status');
    const batteryValue = document.getElementById('ev-battery-value');
    const batteryFill = document.getElementById('ev-battery-fill');
    const powerLabel = document.getElementById('ev-power-label');
    const powerValue = document.getElementById('ev-power-value');
    const timeLabel = document.getElementById('ev-time-label');
    const timeValue = document.getElementById('ev-time-value');
    const energyLabel = document.getElementById('ev-energy-label');
    const energyValue = document.getElementById('ev-energy-value');
    const costLabel = document.getElementById('ev-cost-label');
    const costValue = document.getElementById('ev-cost-value');
    const mode = document.getElementById('ev-mode');
    const payment = document.getElementById('ev-payment');
    const action = document.getElementById('ev-action');
    const logoSource = 'logos/ui/electric_charger.png';

    let latestData = {};
    let hideTimer;
	let warningContext;
	let lastWarningAt = 0;
	const activeWarningTones = new Set();

    function isElectric(data) {
        return data.mode === 'charging' || data.unit === 'kilowatt-hours';
    }

    function formatRemaining(seconds, state) {
        seconds = Number(seconds);

        if (!Number.isFinite(seconds) || (state === 'ready' && seconds <= 0)) return '--';
        if (seconds < 60) return `${Math.max(Math.ceil(seconds), 0)} sec`;

        return `${Math.ceil(seconds / 60)} min`;
    }

	function stopWarningTones() {
		lastWarningAt = 0;

		for (const oscillator of activeWarningTones) {
			try {
				oscillator.stop();
			} catch (_) {
				// The tone may have already ended naturally.
			}
		}

		activeWarningTones.clear();
	}

	function playWarningTone(volume, critical) {
		const AudioContext = window.AudioContext || window.webkitAudioContext;

		if (!AudioContext || volume <= 0) return;

		warningContext ||= new AudioContext();

		const play = () => {
			if (warningContext.state !== 'running') return;

			const now = warningContext.currentTime;
			const oscillator = warningContext.createOscillator();
			const gain = warningContext.createGain();
			const duration = critical ? 0.2 : 0.13;

			oscillator.type = critical ? 'square' : 'sine';
			oscillator.frequency.setValueAtTime(critical ? 610 : 520, now);
			oscillator.frequency.linearRampToValueAtTime(critical ? 860 : 570, now + duration);
			gain.gain.setValueAtTime(0.0001, now);
			gain.gain.exponentialRampToValueAtTime(Math.min(Math.max(volume, 0.001), 0.35), now + 0.012);
			gain.gain.exponentialRampToValueAtTime(0.0001, now + duration);
			oscillator.connect(gain);
			gain.connect(warningContext.destination);
			activeWarningTones.add(oscillator);
			oscillator.onended = () => {
				activeWarningTones.delete(oscillator);
				oscillator.disconnect();
				gain.disconnect();
			};
			oscillator.start(now);
			oscillator.stop(now + duration + 0.01);
		};

		if (warningContext.state === 'suspended') {
			warningContext.resume().then(play).catch(() => {});
			return;
		}

		play();
	}

	function updatePortableWarning(data, packPercent, state) {
		const lowThreshold = Math.min(Math.max(Number(data.lowBatteryPercent) || 20, 0), 100);
		const criticalThreshold = Math.min(Math.max(Number(data.criticalBatteryPercent) || 10, 0), lowThreshold);
		const critical = packPercent <= criticalThreshold;
		const low = packPercent <= lowThreshold;

		meter.classList.toggle('is-portable-low', low && !critical);
		meter.classList.toggle('is-portable-critical', critical);

		if (state !== 'fueling' || !low || data.warningBeeps === false) {
			lastWarningAt = 0;
			return { low, critical };
		}

		const interval = critical
			? Math.max(Number(data.criticalBatteryBeepIntervalMs) || 3500, 750)
			: Math.max(Number(data.lowBatteryBeepIntervalMs) || 7500, 1000);
		const now = Date.now();

		if (now - lastWarningAt >= interval) {
			lastWarningAt = now;
			playWarningTone(Math.max(Number(data.warningBeepVolume) || 0.08, 0), critical);
		}

		return { low, critical };
	}

    function render(incoming) {
        clearTimeout(hideTimer);
        hideTimer = undefined;
        latestData = { ...latestData, ...incoming };
        const data = latestData;
        const rawPercent = Number(data.tankPercent ?? data.fuel);
        const hasPercent = Number.isFinite(rawPercent);
        const percent = hasPercent ? Math.min(Math.max(rawPercent, 0), 100) : 0;
        const currency = typeof data.currency === 'string' ? data.currency : '$';
        const cost = Math.max(Number(data.cost) || 0, 0);
        const energy = Math.max(Number(data.addedVolume) || 0, 0);
        const powerKw = Math.max(Number(data.powerKw) || 0, 0);
        const state = data.state || 'ready';
        const statusText = data.label || 'Charging';
        const isPortableOutput = data.sourceType === 'portable';
        const packCapacity = Math.max(Number(data.packCapacityKwh) || 0, 0);
        const packRemaining = Math.min(Math.max(Number(data.packRemainingKwh) || 0, 0), packCapacity || Number.MAX_SAFE_INTEGER);
        const rawPackPercent = Number(data.packPercent);
        const packPercent = Number.isFinite(rawPackPercent)
            ? Math.min(Math.max(rawPackPercent, 0), 100)
            : (packCapacity > 0 ? (packRemaining / packCapacity) * 100 : 0);

        meter.classList.add('is-electric');
        meter.classList.toggle('is-portable-output', isPortableOutput);
		terminal.hidden = isPortableOutput;
		portableTerminal.hidden = !isPortableOutput;

		if (isPortableOutput) {
			const warning = updatePortableWarning(data, packPercent, state);
			let portableStatusText = state === 'fueling' ? 'OUTPUT' : (state === 'complete' ? 'DONE' : (state === 'stopped' ? 'STOP' : 'READY'));

			if (warning.critical) portableStatusText = data.portableCriticalLabel || 'CRITICAL';
			else if (warning.low) portableStatusText = data.portableLowLabel || 'LOW PACK';

			portableStatus.textContent = portableStatusText;
			portablePackFill.style.width = `${packPercent}%`;
			portablePackValue.textContent = `${packPercent.toFixed(0)}%`;
			portableVehicleValue.textContent = hasPercent ? `${percent.toFixed(0)}%` : '--%';
			portableEnergyValue.textContent = energy.toFixed(2);
			portableTimeValue.textContent = formatRemaining(data.remainingSeconds, state);
			portableTerminal.dataset.state = state;
			return;
		}

		meter.classList.remove('is-portable-low', 'is-portable-critical');
		stopWarningTones();
        logo.src = logoSource;
        logo.alt = '';
        brand.textContent = data.brand || 'SENTINEL CHARGE';
        clock.textContent = new Intl.DateTimeFormat([], { hour: 'numeric', minute: '2-digit' }).format(new Date());
        status.textContent = state === 'fueling' ? `${statusText}...` : statusText;
        batteryValue.textContent = hasPercent ? `${percent.toFixed(0)}%` : '--%';
        batteryValue.setAttribute(
            'aria-label',
            hasPercent ? `${data.levelLabel || 'Battery'} level ${percent.toFixed(0)} percent` : `${data.levelLabel || 'Battery'} level unavailable`,
        );
        batteryFill.style.width = `${percent}%`;
        powerLabel.textContent = data.powerLabel || 'Charging speed';
        powerValue.textContent = powerKw > 0 ? `${powerKw.toFixed(0)} kW` : '-- kW';
        timeLabel.textContent = data.timeLabel || 'Time remaining';
        timeValue.textContent = formatRemaining(data.remainingSeconds, state);
        energyLabel.textContent = data.energyLabel || 'Energy delivered';
        energyValue.textContent = `${energy.toFixed(2)} ${data.unitLabel || 'kWh'}`;
        costLabel.textContent = data.costLabel || 'Cost';
        costValue.textContent = `${currency}${cost.toFixed(2)}`;
        mode.textContent = data.gradeLabel || data.gradeShortLabel || '--';
        payment.textContent = data.paymentLabel || data.paymentShortLabel || '--';
        action.textContent = statusText;
        terminal.dataset.state = state;
    }

    function deactivate() {
        clearTimeout(hideTimer);
        hideTimer = undefined;
        latestData = {};
        meter.classList.remove('is-electric', 'is-portable-output', 'is-portable-low', 'is-portable-critical');
        terminal.hidden = true;
		portableTerminal.hidden = true;
		stopWarningTones();
    }

    function hideAfterFade() {
        clearTimeout(hideTimer);
        latestData = {};
        hideTimer = setTimeout(() => {
            hideTimer = undefined;

            if (meter.classList.contains('is-visible')) return;

            meter.classList.remove('is-electric', 'is-portable-output', 'is-portable-low', 'is-portable-critical');
            terminal.hidden = true;
			portableTerminal.hidden = true;
			stopWarningTones();
        }, 180);
    }

    window.addEventListener('message', (event) => {
        const data = event.data || {};

        if (['show', 'update', 'finish'].includes(data.action)) {
            if (isElectric(data)) {
                render(data);
            } else {
                deactivate();
            }
            return;
        }

        if (data.action === 'hide') hideAfterFade();
    });

    const preview = new URLSearchParams(window.location.search).get('preview');
    const local = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';

    if (local && preview?.startsWith('charging')) {
		const portableOutput = preview === 'charging-portable' || preview === 'charging-portable-low';
		const portableLow = preview === 'charging-portable-low';
        const portableRecharge = preview === 'charging-pack';

        render({
            mode: 'charging',
            sourceType: portableOutput ? 'portable' : (portableRecharge ? 'portable-recharge' : 'station'),
            label: portableRecharge ? 'Recharging pack' : 'Charging',
            tankPercent: portableRecharge ? 68 : 54,
            state: 'fueling',
            addedVolume: portableOutput ? 3.4 : (portableRecharge ? 4.2 : 18.6),
            cost: portableOutput ? 0 : (portableRecharge ? 2.18 : 7.44),
            currency: '$',
            unit: 'kilowatt-hours',
            unitLabel: 'kWh',
            unitPrice: 0.52,
            powerKw: portableOutput ? 7.2 : 150,
            remainingSeconds: portableOutput ? 43 : (portableRecharge ? 15 : 1680),
            powerLabel: 'Charging speed',
            timeLabel: 'Time remaining',
            energyLabel: 'Energy delivered',
            costLabel: 'Cost',
            levelLabel: 'Battery',
            brand: portableOutput ? 'SENTINEL PORTABLE POWER' : (portableRecharge ? 'SENTINEL PACK RECHARGE' : 'SENTINEL EV CHARGING'),
            gradeLabel: portableOutput ? 'Portable' : 'Standard',
            paymentLabel: portableOutput ? 'Pack' : 'Bank',
            packLabel: 'Pack remaining',
            packRemainingKwh: portableOutput ? (portableLow ? 1.5 : 8.6) : undefined,
            packCapacityKwh: portableOutput ? 12 : undefined,
			packPercent: portableOutput ? (portableLow ? 12.5 : 71.7) : undefined,
			warningBeeps: false,
			lowBatteryPercent: 20,
			criticalBatteryPercent: 10,
        });
        meter.classList.add('is-visible');
        meter.setAttribute('aria-hidden', 'false');
    }
})();
