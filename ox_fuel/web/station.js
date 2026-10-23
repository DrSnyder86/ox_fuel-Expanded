(() => {
    const query = new URLSearchParams(window.location.search);
    const mode = query.get('surface');
    if (mode !== 'station' && mode !== 'pump') return;

    document.body.classList.add('world-display');
    if (mode === 'pump') document.body.classList.add('world-pump-display');
    const resource = query.get('resource');
    const surface = query.get('id');
    const local = ['localhost', '127.0.0.1'].includes(window.location.hostname);

    if (resource && surface && !local) {
        fetch(`https://${resource}/stationReady`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({ id: surface }),
        }).catch(() => {});
    }
})();
