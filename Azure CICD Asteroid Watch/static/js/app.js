// Asteroid Watch frontend
// Fetches from OUR Flask API (/api/asteroids), never calls NASA directly.

let chart = null;

function todayISO() {
  return new Date().toISOString().split("T")[0];
}

function addDaysISO(isoDate, days) {
  const d = new Date(isoDate);
  d.setDate(d.getDate() + days);
  return d.toISOString().split("T")[0];
}

function setDefaultDates() {
  const start = todayISO();
  const end = addDaysISO(start, 6);
  document.getElementById("start-date").value = start;
  document.getElementById("end-date").value = end;
}

async function loadAsteroids() {
  const startDate = document.getElementById("start-date").value;
  const endDate = document.getElementById("end-date").value;
  const status = document.getElementById("status");

  status.textContent = "Loading...";

  try {
    const url = `/api/asteroids?start_date=${startDate}&end_date=${endDate}`;
    const res = await fetch(url);
    const data = await res.json();

    if (!res.ok) {
      status.textContent = `Error: ${data.error}`;
      return;
    }

    status.textContent = `Loaded ${data.count} asteroids`;
    renderChart(data.asteroids);
    renderHazardousTable(data.asteroids);
  } catch (err) {
    status.textContent = `Error: ${err.message}`;
  }
}

function renderChart(asteroids) {
  const ctx = document.getElementById("asteroid-chart").getContext("2d");

  const safePoints = [];
  const hazardousPoints = [];

  for (const a of asteroids) {
    const avgDiameter = (a.diameter_km_min + a.diameter_km_max) / 2;
    const point = {
      x: a.date,
      y: a.miss_distance_km,
      r: Math.max(4, Math.min(avgDiameter * 40, 40)), // scale bubble size, clamped
      label: a.name,
      diameter: avgDiameter.toFixed(3),
      velocity: a.velocity_kph.toLocaleString(),
    };
    (a.is_hazardous ? hazardousPoints : safePoints).push(point);
  }

  if (chart) chart.destroy();

  chart = new Chart(ctx, {
    type: "bubble",
    data: {
      datasets: [
        {
          label: "Safe",
          data: safePoints,
          backgroundColor: "rgba(88, 166, 255, 0.6)",
        },
        {
          label: "Potentially Hazardous",
          data: hazardousPoints,
          backgroundColor: "rgba(248, 81, 73, 0.7)",
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: {
          type: "category",
          title: { display: true, text: "Close Approach Date" },
        },
        y: {
          title: { display: true, text: "Miss Distance (km)" },
          ticks: {
            callback: (value) => value.toLocaleString(),
          },
        },
      },
      plugins: {
        tooltip: {
          callbacks: {
            label: (ctx) => {
              const p = ctx.raw;
              return `${p.label}: ${p.diameter} km diameter, ${p.velocity} km/h`;
            },
          },
        },
      },
    },
  });
}

function renderHazardousTable(asteroids) {
  const tbody = document.querySelector("#hazardous-table tbody");
  const noHazardous = document.getElementById("no-hazardous");
  tbody.innerHTML = "";

  const hazardous = asteroids.filter((a) => a.is_hazardous);

  if (hazardous.length === 0) {
    noHazardous.classList.remove("hidden");
    return;
  }
  noHazardous.classList.add("hidden");

  for (const a of hazardous) {
    const avgDiameter = ((a.diameter_km_min + a.diameter_km_max) / 2).toFixed(3);
    const row = document.createElement("tr");
    row.innerHTML = `
      <td>${a.name}</td>
      <td>${a.date}</td>
      <td>${avgDiameter}</td>
      <td>${a.velocity_kph.toLocaleString()}</td>
      <td>${a.miss_distance_km.toLocaleString()}</td>
    `;
    tbody.appendChild(row);
  }
}

document.getElementById("load-btn").addEventListener("click", loadAsteroids);

setDefaultDates();
loadAsteroids();
