let allVehicles = [];
let currentGarage = "";
let selectedVehicle = null;

window.addEventListener('message', function(event) {
    const item = event.data;

    if (item.action === "open") {
        allVehicles = item.vehicles;
        currentGarage = item.garage;
        document.getElementById('garage-name').innerText = currentGarage;
        document.getElementById('vehicle-count').innerText = `Total de ${allVehicles.length} veículos`;
        document.getElementById('garage-app').style.display = 'flex';
        renderVehicleList(allVehicles);
    }

    if (item.action === "close") {
        closeUI();
    }
});

function renderVehicleList(vehicles) {
    const listElement = document.getElementById('vehicle-list');
    listElement.innerHTML = '';

    vehicles.forEach((veh, index) => {
        const card = document.createElement('div');
        card.className = 'vehicle-card animate__animated animate__fadeInUp';
        card.style.animationDelay = `${index * 0.05}s`;
        
        const model = veh.model_name || veh.model;
        const imgUrl = getVehicleImage(model);

        card.innerHTML = `
            <div class="card-img">
                <img src="${imgUrl}" onerror="this.src='https://docs.fivem.net/vehicles/${model}.webp'; this.onerror=null;">
            </div>
            <div class="card-info">
                <h3>${veh.name}</h3>
                <p>${veh.plate}</p>
            </div>
        `;

        card.onclick = () => selectVehicle(veh, card);
        listElement.appendChild(card);
    });
}

function selectVehicle(veh, cardElement) {
    document.querySelectorAll('.vehicle-card').forEach(c => c.classList.remove('active'));
    cardElement.classList.add('active');

    selectedVehicle = veh;
    
    document.getElementById('no-selection').style.display = 'none';
    const content = document.getElementById('vehicle-content');
    content.style.display = 'block';

    const model = veh.model_name || veh.model;
    document.getElementById('display-name').innerText = veh.name;
    document.getElementById('display-plate').innerText = veh.plate;
    document.getElementById('main-vehicle-image').src = getVehicleImage(model);
    
    updateStat('fuel', veh.fuel);
    updateStat('engine', (veh.engine || 1000) / 10);
    updateStat('body', (veh.body || 1000) / 10);
    
    document.getElementById('status-text').innerText = veh.state_text || "Na Garagem";
    
    const takeOutBtn = document.getElementById('take-out-btn');
    if (veh.state !== 1) {
        takeOutBtn.disabled = true;
        takeOutBtn.style.opacity = '0.5';
        takeOutBtn.innerText = "VEÍCULO FORA";
    } else {
        takeOutBtn.disabled = false;
        takeOutBtn.style.opacity = '1';
        takeOutBtn.innerHTML = '<i class="fas fa-sign-out-alt"></i> RETIRAR VEÍCULO';
    }
}

function updateStat(id, value) {
    const val = Math.round(value);
    document.getElementById(`${id}-text`).innerText = `${val}%`;
    document.getElementById(`${id}-bar`).style.width = `${val}%`;
    const bar = document.getElementById(`${id}-bar`);
    if (val < 30) bar.style.background = '#ff4d4d';
    else if (val < 70) bar.style.background = '#ffb300';
    else bar.style.background = '#3d8bff';
}

function getVehicleImage(model) {
    return `https://cfx-nui-ox_inventory/web/images/${model.toLowerCase()}.png`;
}

document.getElementById('search-input').oninput = function(e) {
    const term = e.target.value.toLowerCase();
    const filtered = allVehicles.filter(v => 
        v.name.toLowerCase().includes(term) || v.plate.toLowerCase().includes(term)
    );
    renderVehicleList(filtered);
};

document.getElementById('take-out-btn').onclick = function() {
    if (selectedVehicle) {
        fetch(`https://${GetParentResourceName()}/takeOutVehicle`, {
            method: 'POST',
            body: JSON.stringify({
                plate: selectedVehicle.plate,
                garage: currentGarage
            })
        });
        closeUI();
    }
};

function closeUI() {
    document.getElementById('garage-app').style.display = 'none';
    fetch(`https://${GetParentResourceName()}/closeUI`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

document.onkeyup = function(data) {
    if (data.key === 'Escape') closeUI();
};
