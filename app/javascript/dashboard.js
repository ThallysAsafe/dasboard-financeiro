const DASHBOARD_QUERY = `
    query Dashboard($limit: Int!) {
        balance
        totalIncome
        totalExpense
        wallets { id name balance totalIncome totalExpense }
        incomes: transactions(kind: INCOME, limit: $limit) { id description amount date category recurringTransactionId wallet { id name } }
        expenses: transactions(kind: EXPENSE, limit: $limit) { id description amount date category recurringTransactionId wallet { id name } }
        recurringIncomes: recurringTransactions(kind: INCOME) { id description amount dayOfMonth startDate endDate category active nextOccurrence wallet { id name } }
        recurringExpenses: recurringTransactions(kind: EXPENSE) { id description amount dayOfMonth startDate endDate category active nextOccurrence wallet { id name } }
    }
`;

// O cookie de sessão só vale em requisições com este cabeçalho (defesa contra CSRF).
const AJAX_HEADERS = { 'X-Requested-With': 'XMLHttpRequest' };
const PAGE_SIZE = 100;
const state = { wallets: [], incomes: [], expenses: [], recurring: [], hasMore: { income: false, expense: false } };
let modalState = { kind: 'income', mode: 'create', id: null, recurring: false };

// Sem handlers inline (a CSP os bloqueia): cada elemento interativo declara
// data-action e o clique é despachado aqui.
const ACTIONS = {
    'logout': () => handleLogout(),
    'open-create': (el) => openCreate(el.dataset.kind),
    'close-modal': () => closeModal(),
    'edit': (el) => openEdit(el.dataset.kind, el.dataset.id),
    'delete': (el) => deleteEntry(el.dataset.kind, el.dataset.id),
    'load-more': (el) => loadMore(el.dataset.kind),
    'edit-recurring': (el) => openEditRecurring(el.dataset.kind, el.dataset.id),
    'toggle-recurring': (el) => toggleRecurringActive(el.dataset.kind, el.dataset.id),
    'delete-recurring': (el) => deleteRecurring(el.dataset.kind, el.dataset.id)
};

function bindEvents() {
    document.addEventListener('click', (event) => {
        const el = event.target.closest('[data-action]');
        if (el && ACTIONS[el.dataset.action]) ACTIONS[el.dataset.action](el);
    });
    document.getElementById('entryModal').addEventListener('click', handleOverlayClick);
    document.getElementById('entryForm').addEventListener('submit', handleEntrySubmit);
    document.getElementById('entryRecurring').addEventListener('change', toggleRecurringFields);
}

// O token fica num cookie HttpOnly: o JS não o lê. A sessão é verificada
// perguntando ao servidor quem é o usuário.
async function loadCurrentUser() {
    const response = await fetch('/api/v1/auth/me', { headers: AJAX_HEADERS });
    if (response.status === 401) {
        window.location.href = '/login';
        return false;
    }
    const data = await response.json();
    document.getElementById('userEmailDisplay').textContent = data.user.email;
    return true;
}

document.addEventListener('DOMContentLoaded', async () => {
    bindEvents();

    if (!(await loadCurrentUser())) return;

    // Falha de sincronização não pode derrubar a página: no pior caso as listas
    // ficam sem os lançamentos recorrentes mais recentes.
    try {
        const created = await syncRecurring();
        if (created > 0) {
            showAlert('info', `${created} ${created === 1 ? 'lançamento recorrente foi gerado' : 'lançamentos recorrentes foram gerados'} automaticamente.`);
        }
    } catch (error) {
        console.warn('Não foi possível sincronizar as recorrências:', error);
    }

    await loadDashboard();
});

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') closeModal();
});

// --- Comunicação ---

async function graphqlRequest(query, variables = {}) {
    const response = await fetch('/graphql', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            ...AJAX_HEADERS
        },
        body: JSON.stringify({ query, variables })
    });

    const result = await response.json();

    if (result.errors && result.errors.length > 0) {
        if (result.errors.some(err => err.message.includes('autenticado'))) handleLogout();
        throw new Error(result.errors.map(err => err.message).join(' | '));
    }

    return result.data;
}

async function syncRecurring() {
    const data = await graphqlRequest('mutation { syncRecurringEntries { createdCount errors } }');
    return data.syncRecurringEntries.createdCount;
}

async function loadDashboard() {
    try {
        const data = await graphqlRequest(DASHBOARD_QUERY, { limit: PAGE_SIZE });

        state.wallets = data.wallets || [];
        state.incomes = data.incomes || [];
        state.expenses = data.expenses || [];
        state.hasMore.income = state.incomes.length === PAGE_SIZE;
        state.hasMore.expense = state.expenses.length === PAGE_SIZE;
        state.recurring = [
            ...(data.recurringIncomes || []).map(item => ({ ...item, kind: 'income' })),
            ...(data.recurringExpenses || []).map(item => ({ ...item, kind: 'expense' }))
        ];

        document.getElementById('balanceValue').textContent = formatCurrency(data.balance);
        document.getElementById('incomeValue').textContent = formatCurrency(data.totalIncome);
        document.getElementById('expenseValue').textContent = formatCurrency(data.totalExpense);

        renderWallets();
        renderEntries('income');
        renderEntries('expense');
        renderRecurring();
    } catch (error) {
        console.error('Erro ao carregar o dashboard:', error);
        showAlert('error', `Não foi possível carregar os dados: ${error.message}`);
    }
}

// --- Renderização ---

function renderWallets() {
    const grid = document.getElementById('walletsGrid');

    if (state.wallets.length === 0) {
        grid.innerHTML = `
            <div class="card wallet-card">
                <div class="wallet-name">Nenhuma carteira cadastrada</div>
                <div class="wallet-balance">R$ 0,00</div>
            </div>
        `;
        return;
    }

    grid.innerHTML = state.wallets.map(wallet => `
        <div class="card wallet-card">
            <div class="wallet-name">${escapeHtml(wallet.name)}</div>
            <div class="wallet-balance">${formatCurrency(wallet.balance)}</div>
            <div style="font-size: 12px; color: #94a3b8; margin-top: 8px;">
                + ${formatCurrency(wallet.totalIncome)} | - ${formatCurrency(wallet.totalExpense)}
            </div>
        </div>
    `).join('');
}

function renderEntries(kind) {
    const isIncome = kind === 'income';
    const entries = isIncome ? state.incomes : state.expenses;
    const container = document.getElementById(isIncome ? 'incomesList' : 'expensesList');

    if (entries.length === 0) {
        container.innerHTML = `<div class="empty-state">Nenhuma ${isIncome ? 'receita' : 'despesa'} cadastrada ainda.</div>`;
        return;
    }

    container.innerHTML = entries.map(entry => {
        const fromRecurrence = entry.recurringTransactionId;
        return `
            <div class="entry-row">
                <div class="entry-date">${formatDate(entry.date)}</div>
                <div class="entry-description">
                    <span>${escapeHtml(entry.description)}</span>
                    ${fromRecurrence ? '<span class="badge badge-recurring">🔁 recorrente</span>' : ''}
                </div>
                <div class="entry-meta">${entryMeta(entry)}</div>
                <div class="entry-amount ${isIncome ? 'positive' : 'negative'}">
                    ${isIncome ? '+' : '-'} ${formatCurrency(entry.amount)}
                </div>
                <div class="entry-actions">
                    <button class="btn-icon" data-action="edit" data-kind="${kind}" data-id="${entry.id}">Editar</button>
                    <button class="btn-icon danger" data-action="delete" data-kind="${kind}" data-id="${entry.id}">Excluir</button>
                </div>
            </div>
        `;
    }).join('') + (state.hasMore[kind]
        ? `<button class="btn-icon btn-load-more" data-action="load-more" data-kind="${kind}">Carregar mais</button>`
        : '');
}

// Busca a próxima página e anexa à lista; os totais do topo já cobrem tudo.
async function loadMore(kind) {
    const list = kind === 'income' ? state.incomes : state.expenses;

    try {
        const data = await graphqlRequest(
            `query($kind: TransactionKind!, $limit: Int!, $offset: Int!) {
                transactions(kind: $kind, limit: $limit, offset: $offset) {
                    id description amount date category recurringTransactionId wallet { id name }
                }
            }`,
            { kind: kind.toUpperCase(), limit: PAGE_SIZE, offset: list.length }
        );
        const page = data.transactions || [];
        list.push(...page);
        state.hasMore[kind] = page.length === PAGE_SIZE;
        renderEntries(kind);
    } catch (error) {
        showAlert('error', `Não foi possível carregar mais: ${error.message}`);
    }
}

function renderRecurring() {
    const container = document.getElementById('recurringList');

    if (state.recurring.length === 0) {
        container.innerHTML = `<div class="empty-state">Nenhuma recorrência cadastrada. Marque "Repetir todo mês" ao criar uma receita ou despesa.</div>`;
        return;
    }

    container.innerHTML = state.recurring.map(template => `
        <div class="entry-row ${template.active ? '' : 'paused'}">
            <div class="entry-date">todo dia ${template.dayOfMonth}</div>
            <div class="entry-description">
                <span>${escapeHtml(template.description)}</span>
                <span class="badge badge-${template.kind}">${template.kind === 'income' ? 'Receita' : 'Despesa'}</span>
                ${template.active ? '' : '<span class="badge badge-paused">pausada</span>'}
            </div>
            <div class="entry-meta">${recurringMeta(template)}</div>
            <div class="entry-amount ${template.kind === 'income' ? 'positive' : 'negative'}">
                ${formatCurrency(template.amount)}
            </div>
            <div class="entry-actions">
                <button class="btn-icon" data-action="edit-recurring" data-kind="${template.kind}" data-id="${template.id}">Editar</button>
                <button class="btn-icon" data-action="toggle-recurring" data-kind="${template.kind}" data-id="${template.id}">${template.active ? 'Pausar' : 'Retomar'}</button>
                <button class="btn-icon danger" data-action="delete-recurring" data-kind="${template.kind}" data-id="${template.id}">Excluir</button>
            </div>
        </div>
    `).join('');
}

function entryMeta(entry) {
    const parts = [];
    if (entry.category) parts.push(escapeHtml(entry.category));
    if (entry.wallet) parts.push(escapeHtml(entry.wallet.name));
    return parts.join(' • ') || '—';
}

function recurringMeta(template) {
    const parts = [`desde ${formatMonthYear(template.startDate)}`];
    if (template.endDate) parts.push(`até ${formatDate(template.endDate)}`);
    if (template.active && template.nextOccurrence) parts.push(`próximo: ${formatDate(template.nextOccurrence)}`);
    if (template.wallet) parts.push(escapeHtml(template.wallet.name));
    return parts.join(' • ');
}

function renderWalletOptions(selectedId) {
    const select = document.getElementById('entryWallet');
    const options = ['<option value="">Sem carteira</option>'].concat(
        state.wallets.map(wallet => `<option value="${wallet.id}">${escapeHtml(wallet.name)}</option>`)
    );
    select.innerHTML = options.join('');
    select.value = selectedId == null ? '' : String(selectedId);
}

// --- Modal ---

function openCreate(kind) {
    modalState = { kind, mode: 'create', id: null, recurring: false };

    document.getElementById('entryForm').reset();
    document.getElementById('entryDate').value = todayISO();
    document.getElementById('entryRecurring').disabled = false;
    document.getElementById('entryActiveWrapper').style.display = 'none';
    // Pré-seleciona a primeira carteira: lançamento sem carteira é sempre
    // possível, mas raramente é o que o usuário quer.
    renderWalletOptions(state.wallets.length ? state.wallets[0].id : null);
    toggleRecurringFields();

    document.getElementById('modalTitle').textContent = kind === 'income' ? 'Nova Receita' : 'Nova Despesa';
    openModal();
}

function openEdit(kind, id) {
    const entries = kind === 'income' ? state.incomes : state.expenses;
    const entry = entries.find(item => String(item.id) === String(id));
    if (!entry) return;

    modalState = { kind, mode: 'edit', id, recurring: false };

    document.getElementById('entryForm').reset();
    document.getElementById('entryDescription').value = entry.description;
    document.getElementById('entryAmount').value = entry.amount;
    document.getElementById('entryDate').value = entry.date;
    document.getElementById('entryCategory').value = entry.category || '';
    renderWalletOptions(entry.wallet ? entry.wallet.id : null);

    // Um lançamento avulso não vira recorrência (e vice-versa): são registros
    // de naturezas diferentes.
    document.getElementById('entryRecurring').checked = false;
    document.getElementById('entryRecurring').disabled = true;
    document.getElementById('entryActiveWrapper').style.display = 'none';
    toggleRecurringFields();

    document.getElementById('modalTitle').textContent = kind === 'income' ? 'Editar Receita' : 'Editar Despesa';
    openModal();
}

function openEditRecurring(kind, id) {
    const template = state.recurring.find(item => item.kind === kind && String(item.id) === String(id));
    if (!template) return;

    modalState = { kind, mode: 'edit', id, recurring: true };

    document.getElementById('entryForm').reset();
    document.getElementById('entryDescription').value = template.description;
    document.getElementById('entryAmount').value = template.amount;
    document.getElementById('entryDate').value = template.startDate;
    document.getElementById('entryCategory').value = template.category || '';
    renderWalletOptions(template.wallet ? template.wallet.id : null);

    document.getElementById('entryRecurring').checked = true;
    document.getElementById('entryRecurring').disabled = true;
    document.getElementById('entryDayOfMonth').value = template.dayOfMonth;
    document.getElementById('entryEndDate').value = template.endDate || '';
    document.getElementById('entryActive').checked = template.active;
    document.getElementById('entryActiveWrapper').style.display = 'flex';
    toggleRecurringFields();

    document.getElementById('modalTitle').textContent = kind === 'income' ? 'Editar Receita Recorrente' : 'Editar Despesa Recorrente';
    openModal();
}

function toggleRecurringFields() {
    const enabled = document.getElementById('entryRecurring').checked;
    modalState.recurring = enabled;

    document.getElementById('recurringFields').style.display = enabled ? 'block' : 'none';
    document.getElementById('entryDateLabel').textContent = enabled ? 'Início' : 'Data';

    const dayField = document.getElementById('entryDayOfMonth');
    dayField.required = enabled;

    if (enabled && !dayField.value) {
        const chosen = document.getElementById('entryDate').value;
        dayField.value = chosen ? parseInt(chosen.split('-')[2], 10) : new Date().getDate();
    }
}

function openModal() {
    hideModalAlert();
    document.getElementById('entryModal').classList.add('open');
    document.getElementById('entryDescription').focus();
}

function closeModal() {
    document.getElementById('entryModal').classList.remove('open');
}

function handleOverlayClick(event) {
    if (event.target === event.currentTarget) closeModal();
}

// --- Escrita ---

async function handleEntrySubmit(event) {
    event.preventDefault();

    const button = document.getElementById('entrySubmit');
    const originalLabel = button.textContent;
    hideModalAlert();

    const walletValue = document.getElementById('entryWallet').value;
    const variables = {
        description: document.getElementById('entryDescription').value.trim(),
        amount: parseFloat(document.getElementById('entryAmount').value),
        category: document.getElementById('entryCategory').value.trim() || null,
        walletId: walletValue || null
    };
    const args = [
        { name: 'description', type: 'String!' },
        { name: 'amount', type: 'Float!' },
        { name: 'category', type: 'String' },
        { name: 'walletId', type: 'ID' }
    ];

    if (modalState.recurring) {
        variables.dayOfMonth = parseInt(document.getElementById('entryDayOfMonth').value, 10);
        variables.startDate = document.getElementById('entryDate').value;
        variables.endDate = document.getElementById('entryEndDate').value || null;
        args.push(
            { name: 'dayOfMonth', type: 'Int!' },
            { name: 'startDate', type: 'ISO8601Date!' },
            { name: 'endDate', type: 'ISO8601Date' }
        );

        if (modalState.mode === 'edit') {
            variables.active = document.getElementById('entryActive').checked;
            args.push({ name: 'active', type: 'Boolean' });
        }
    } else {
        variables.date = document.getElementById('entryDate').value;
        args.push({ name: 'date', type: 'ISO8601Date!' });
    }

    if (modalState.mode === 'edit') {
        variables.id = modalState.id;
        args.unshift({ name: 'id', type: 'ID!' });
    } else {
        // O tipo só é definido na criação; edição não reclassifica o lançamento.
        variables.kind = modalState.kind.toUpperCase();
        args.unshift({ name: 'kind', type: 'TransactionKind!' });
    }

    const operation = mutationName();
    const payload = modalState.recurring ? 'generatedCount errors' : 'errors';
    const declaration = args.map(arg => `$${arg.name}: ${arg.type}`).join(', ');
    const forwarding = args.map(arg => `${arg.name}: $${arg.name}`).join(', ');
    const mutation = `mutation(${declaration}) { ${operation}(${forwarding}) { ${payload} } }`;

    button.disabled = true;
    button.textContent = 'Salvando...';

    try {
        const result = (await graphqlRequest(mutation, variables))[operation];

        if (result.errors.length > 0) {
            showModalAlert(result.errors.join(' • '));
            return;
        }

        closeModal();
        await loadDashboard();
        showAlert('success', savedMessage(result.generatedCount));
    } catch (error) {
        showModalAlert(error.message);
    } finally {
        button.disabled = false;
        button.textContent = originalLabel;
    }
}

function mutationName() {
    const base = modalState.recurring ? 'recurringTransaction' : 'transaction';
    return base + (modalState.mode === 'create' ? 'Create' : 'Update');
}

function savedMessage(generatedCount) {
    if (modalState.recurring && generatedCount > 0) {
        return `Recorrência salva. ${generatedCount} ${generatedCount === 1 ? 'lançamento gerado' : 'lançamentos gerados'}.`;
    }
    return modalState.recurring ? 'Recorrência salva com sucesso.' : 'Lançamento salvo com sucesso.';
}

async function deleteEntry(kind, id) {
    const entries = kind === 'income' ? state.incomes : state.expenses;
    const entry = entries.find(item => String(item.id) === String(id));
    if (!entry || !confirm(`Excluir "${entry.description}"?`)) return;

    const operation = 'transactionDelete';
    await runMutation(
        `mutation($id: ID!) { ${operation}(id: $id) { errors } }`,
        { id },
        operation,
        'Lançamento excluído.'
    );
}

async function deleteRecurring(kind, id) {
    const template = state.recurring.find(item => item.kind === kind && String(item.id) === String(id));
    if (!template) return;

    const confirmed = confirm(
        `Excluir a recorrência "${template.description}"?\n\n` +
        'Os lançamentos já gerados serão mantidos no histórico.'
    );
    if (!confirmed) return;

    const operation = 'recurringTransactionDelete';
    await runMutation(
        `mutation($id: ID!) { ${operation}(id: $id) { errors } }`,
        { id },
        operation,
        'Recorrência excluída. Os lançamentos já gerados foram mantidos.'
    );
}

async function toggleRecurringActive(kind, id) {
    const template = state.recurring.find(item => item.kind === kind && String(item.id) === String(id));
    if (!template) return;

    const operation = 'recurringTransactionUpdate';
    await runMutation(
        `mutation($id: ID!, $active: Boolean) { ${operation}(id: $id, active: $active) { generatedCount errors } }`,
        { id, active: !template.active },
        operation,
        template.active ? 'Recorrência pausada.' : 'Recorrência retomada.'
    );
}

async function runMutation(mutation, variables, operation, successMessage) {
    try {
        const result = (await graphqlRequest(mutation, variables))[operation];

        if (result.errors.length > 0) {
            showAlert('error', result.errors.join(' • '));
            return;
        }

        await loadDashboard();
        showAlert('success', successMessage);
    } catch (error) {
        showAlert('error', error.message);
    }
}

// --- Utilitários ---

function formatCurrency(value) {
    return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(value || 0);
}

// Split puro em vez de new Date(): '2026-08-09' é meia-noite UTC e viraria
// 08/08 em qualquer fuso a oeste de Greenwich.
function formatDate(iso) {
    if (!iso) return '--';
    const [year, month, day] = iso.split('-');
    return `${day}/${month}/${year}`;
}

function formatMonthYear(iso) {
    if (!iso) return '--';
    const [year, month] = iso.split('-');
    return `${month}/${year}`;
}

// toISOString() também é UTC: depois das 21h em Brasília devolveria amanhã.
function todayISO() {
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${now.getFullYear()}-${month}-${day}`;
}

function escapeHtml(str) {
    return String(str == null ? '' : str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

let alertTimer = null;

function showAlert(kind, message) {
    const box = document.getElementById('pageAlert');
    box.textContent = message;
    box.className = `alert-message alert-${kind}`;
    box.style.display = 'block';

    clearTimeout(alertTimer);
    alertTimer = setTimeout(() => { box.style.display = 'none'; }, 5000);
}

function showModalAlert(message) {
    const box = document.getElementById('modalAlert');
    box.textContent = message;
    box.className = 'alert-message alert-error';
    box.style.display = 'block';
}

function hideModalAlert() {
    const box = document.getElementById('modalAlert');
    box.style.display = 'none';
    box.className = 'alert-message';
}

async function handleLogout() {
    // Revoga a sessão no servidor (que também apaga o cookie); se a chamada
    // falhar, segue para o login do mesmo jeito.
    try {
        await fetch('/api/v1/auth/logout', { method: 'POST', headers: AJAX_HEADERS });
    } catch (e) { /* sem rede */ }
    window.location.href = '/login';
}
