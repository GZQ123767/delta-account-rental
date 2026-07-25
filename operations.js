(function(){
  const escape=value=>String(value??'').replace(/[&<>'"]/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]));
  const format=value=>Number(value||0).toLocaleString('zh-CN');
  const settings={support_contact:'644373420@qq.com',payment_instructions:'订单提交后由管理员通过订单联系方式联系。未核对订单编号和金额前，请勿转账。'};

  const css=document.createElement('link');css.rel='stylesheet';css.href='operations.css';document.head.appendChild(css);

  const loginForm=document.querySelector('#loginForm');
  const forgot=document.createElement('button');forgot.type='button';forgot.className='forgot-link';forgot.textContent='忘记密码？发送重置邮件';loginForm.appendChild(forgot);
  forgot.onclick=async()=>{const email=loginForm.elements.email.value.trim();if(!email){show('请先填写登录邮箱');loginForm.elements.email.focus();return}setBusy(forgot,true,'发送中...');const {error}=await client.auth.resetPasswordForEmail(email,{redirectTo:location.origin+location.pathname});setBusy(forgot,false);show(error?friendlyError(error):'重置邮件已发送，请前往邮箱查看')};

  const userArea=document.querySelector('#authUser');
  const passwordBox=document.createElement('section');passwordBox.className='operations-box';passwordBox.innerHTML='<strong>登录安全</strong><p>建议首次登录后修改临时密码，至少使用 8 位字符。</p><label>新密码<input id="newAccountPassword" type="password" minlength="8" autocomplete="new-password" placeholder="输入新的登录密码"></label><button id="updateAccountPassword" type="button">修改密码</button>';
  userArea.insertBefore(passwordBox,document.querySelector('#logoutButton'));
  passwordBox.querySelector('button').onclick=async event=>{const password=passwordBox.querySelector('input').value;if(password.length<8){show('新密码至少需要 8 位');return}setBusy(event.currentTarget,true);const {error}=await client.auth.updateUser({password});setBusy(event.currentTarget,false);if(error){show(friendlyError(error));return}passwordBox.querySelector('input').value='';show('密码已修改，请妥善保管')};

  const tabs=document.querySelector('.admin-tabs');tabs.classList.add('four-tabs');
  const settingsTab=document.createElement('button');settingsTab.className='admin-tab';settingsTab.dataset.adminTab='settings';settingsTab.textContent='经营设置';tabs.appendChild(settingsTab);
  const settingsPane=document.createElement('section');settingsPane.className='admin-pane';settingsPane.id='adminSettings';settingsPane.innerHTML='<div class="operations-box"><strong>对外联系与付款说明</strong><p>客户下单后可在订单管理中查看联系方式。这里的信息会公开显示在租用规则下方。</p><label>官方联系方式<input id="settingSupport" maxlength="100"></label><label>付款说明<textarea id="settingPayment" maxlength="300"></textarea></label><button id="savePlatformSettings" type="button">保存经营设置</button></div>';
  document.querySelector('.admin-content').appendChild(settingsPane);
  settingsTab.onclick=()=>{document.querySelectorAll('.admin-tab').forEach(item=>item.classList.toggle('active',item===settingsTab));document.querySelectorAll('.admin-pane').forEach(item=>item.classList.toggle('active',item===settingsPane));loadSettingsForm()};

  const support=document.createElement('div');support.className='public-support';support.innerHTML='<strong>官方联系</strong><span id="publicSupportContact"></span><span id="publicPaymentInstructions"></span>';document.querySelector('#rules>div').appendChild(support);
  async function loadPublicSettings(){const {data,error}=await client.rpc('get_public_settings');if(!error)(data||[]).forEach(item=>settings[item.key]=item.value);document.querySelector('#publicSupportContact').textContent=`联系方式：${settings.support_contact}`;document.querySelector('#publicPaymentInstructions').textContent=settings.payment_instructions}
  async function loadSettingsForm(){await loadPublicSettings();document.querySelector('#settingSupport').value=settings.support_contact;document.querySelector('#settingPayment').value=settings.payment_instructions}
  document.querySelector('#savePlatformSettings').onclick=async event=>{const supportContact=document.querySelector('#settingSupport').value.trim(),instructions=document.querySelector('#settingPayment').value.trim();setBusy(event.currentTarget,true);const {error}=await client.rpc('update_public_settings',{support_contact:supportContact,payment_instructions:instructions});setBusy(event.currentTarget,false);if(error){show(friendlyError(error));return}settings.support_contact=supportContact;settings.payment_instructions=instructions;await loadPublicSettings();show('经营设置已保存')};

  const originalLoadAccounts=loadAccounts;
  loadAccounts=async function(){await client.rpc('release_expired_orders');return originalLoadAccounts()};
  loadMyOrders=async function(){
    if(!session)return;
    const {data,error}=await client.from('orders').select('*,listings(title)').eq('renter_id',session.user.id).order('created_at',{ascending:false});
    if(error){document.querySelector('#myOrders').innerHTML=`<div class="error-box">${escape(friendlyError(error))}</div>`;return}
    document.querySelector('#myOrders').innerHTML=data?.length?data.map(item=>{const pending=item.status==='pending'&&item.payment_status==='pending';const expiry=pending&&item.payment_expires_at?`<br><span class="expiry-note">请在 ${new Date(item.payment_expires_at).toLocaleString('zh-CN')} 前完成联系，超时自动释放</span>`:'';const active=item.status==='active'&&item.expires_at?`<br>到期：${new Date(item.expires_at).toLocaleString('zh-CN')}`:'';return `<article class="record-card"><strong>${escape(item.listings?.title||'账号订单')} ${statusChip(item.status)}</strong><p>${format(item.coins_amount)}万哈夫币 · ${item.duration_days}天 · 租金¥${format(item.rental_fee)} · 押金¥${format(item.deposit)}<br>支付：${labels[item.payment_status]||item.payment_status} · ${new Date(item.created_at).toLocaleString('zh-CN')}${expiry}${active}</p>${pending?`<div class="order-actions-inline"><small>尚未确认收款</small><button class="cancel-own-order" data-cancel-own="${item.id}">取消订单</button></div>`:''}</article>`}).join(''):'<div class="empty-small">暂无订单</div>';
  };
  document.querySelector('#myOrders').onclick=async event=>{const button=event.target.closest('[data-cancel-own]');if(!button)return;setBusy(button,true,'取消中...');const {error}=await client.rpc('cancel_my_pending_order',{target_order:button.dataset.cancelOwn});setBusy(button,false);if(error){show(friendlyError(error));return}show('订单已取消，账号已经释放');await Promise.all([loadMyOrders(),loadAccounts()])};
  document.querySelector('#refreshOrders').onclick=loadMyOrders;
  document.querySelector('#adminButton').addEventListener('click',loadSettingsForm);
  client.auth.onAuthStateChange(event=>{if(event==='PASSWORD_RECOVERY'){openPanel('authDrawer');show('请在账户中心设置新密码')}});

  loadPublicSettings();
  loadAccounts();
  if(session)loadMyOrders();
})();
