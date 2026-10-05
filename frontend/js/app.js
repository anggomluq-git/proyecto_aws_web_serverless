// Pide el numero de visitas a la API (ruta relativa, la reenvia CloudFront).
fetch("/visitas")
  .then(response => {
    // Si la API responde con error (403, 500...), lo tratamos como fallo.
    if (!response.ok) throw new Error("HTTP " + response.status);
    return response.json();
  })
  .then(data => {
    // Muestra el contador 
    const contador = document.getElementById("visitor-count");
    contador.textContent = Number(data.num_visitas).toLocaleString("es-ES");
  })
  .catch(error => {
    // Si algo falla, se registra el error y se muestra un guion.
    console.error("Error al cargar el contador:", error);
    document.getElementById("visitor-count").textContent = "—";
  });