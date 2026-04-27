const elements = {
    app: document.getElementById('app'),
    name: document.getElementById('vehicle-name'),
    plate: document.getElementById('vehicle-plate'),
    fuelValue: document.getElementById('fuel-value'),
    fuelFill: document.getElementById('fuel-fill'),
    engineValue: document.getElementById('engine-value'),
    engineFill: document.getElementById('engine-fill'),
    bodyValue: document.getElementById('body-value'),
    bodyFill: document.getElementById('body-fill'),
};

window.addEventListener('message', (event) => {
    const data = event.data;

    if (data.type === 'UPDATE_VEHICLE') {
        updateUI(data.payload);
        elements.app.classList.remove('hidden');
    } else if (data.type === 'HIDE_UI') {
        elements.app.classList.add('hidden');
    }
});

function updateUI(payload) {
    if (payload.name) elements.name.textContent = payload.name;
    if (payload.plate) elements.plate.textContent = payload.plate;
    
    if (payload.fuel !== undefined) {
        const fuel = Math.floor(payload.fuel);
        elements.fuelValue.textContent = `${fuel}%`;
        elements.fuelFill.style.width = `${fuel}%`;
    }
    
    if (payload.engine !== undefined) {
        const engine = Math.floor(payload.engine);
        elements.engineValue.textContent = `${engine}%`;
        elements.engineFill.style.width = `${engine}%`;
    }
    
    if (payload.body !== undefined) {
        const body = Math.floor(payload.body);
        elements.bodyValue.textContent = `${body}%`;
        elements.bodyFill.style.width = `${body}%`;
    }
}

// Inicialização opcional ou heartbeat se necessário
console.log('Showroom DUI Loaded');
