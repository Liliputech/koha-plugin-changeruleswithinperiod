$(document).ready(async function() {
    const smartrulespath = '/cgi-bin/koha/admin/smart-rules.pl';
    if (window.location.pathname.startsWith(smartrulespath)) {
	    const htmlResponse = await fetch('/api/v1/contrib/changerules/static/changerules.html');
	    if (!htmlResponse.ok)
		throw new Error('error while fetching static ressources');

	    const htmlContent = await htmlResponse.text();
	    $('h1.parameters').append(htmlContent);

		const queryParams = new URLSearchParams(window.location.search);
    	branch = queryParams.get('branch');
		if (!branch || branch == '*') { branch = 'default' };
	    const apiResponse = await fetch('/api/v1/contrib/changerules/config');
	    if (!apiResponse.ok)
		throw new Error('error while fetching changerules config');

	    const data = await apiResponse.json();
		document.querySelector('#changerules-circ a.btn').textContent = data.configure_link;
		warning_element = $('#changerules');
		warning_element.text(data.alert_warning);
		if ( data.active.includes(branch) ) {
			console.log('circulation rules are overwritten');
			warning_element.html(data.alert_danger);
			warning_element.addClass('alert-danger');
		}
    }
});
