async function handleLogin(event) {
    event.preventDefault();
    
    const emailInput = document.getElementById('email');
    const passwordInput = document.getElementById('password');
    const btnSubmit = document.getElementById('btnSubmit');
    const alertMessage = document.getElementById('alertMessage');

    const email = emailInput.value.trim();
    const password = passwordInput.value;
    
    // Esconde alertas anteriores
    alertMessage.style.display = 'none';
    alertMessage.className = 'alert-message';
    
    // Estado de carregamento
    btnSubmit.disabled = true;
    btnSubmit.textContent = 'Entrando...';

    try {
        const response = await fetch('/api/v1/auth/login', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ email, password })
        });

        const data = await response.json();

        if (response.ok) {
            // O token JWT vem num cookie HttpOnly gravado pelo servidor;
            // o JS da página nunca o vê.
            alertMessage.textContent = 'Login realizado com sucesso! Redirecionando...';
            alertMessage.classList.add('alert-success');
            alertMessage.style.display = 'block';

            setTimeout(() => {
                window.location.href = '/dashboard';
            }, 1000);
        } else {
            alertMessage.textContent = data.error || 'Falha ao autenticar';
            alertMessage.classList.add('alert-error');
            alertMessage.style.display = 'block';
        }
    } catch (error) {
        console.error('Erro na requisição:', error);
        alertMessage.textContent = 'Erro ao conectar ao servidor. Tente novamente.';
        alertMessage.classList.add('alert-error');
        alertMessage.style.display = 'block';
    } finally {
        btnSubmit.disabled = false;
        btnSubmit.textContent = 'Entrar';
    }
}

document.getElementById('loginForm').addEventListener('submit', handleLogin);
