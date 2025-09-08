function changeDisplay(start_date, end_date) {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const startDate = new Date(start_date);
    const endDate = new Date(end_date);

    if (today >= startDate && today < endDate) {
	$('#changerules-in').removeClass('d-none');
	$('#changerules-out').addClass('d-none');
    }
}

$(document).ready(async function() {
    const smartrulespath = '/cgi-bin/koha/admin/smart-rules.pl';
    if (window.location.pathname.startsWith(smartrulespath)) {
	try {
	    const htmlResponse = await fetch('/api/v1/contrib/changerules/static/changerules.html');
	    if (!htmlResponse.ok)
		throw new Error('error while fetching static ressources');

	    const htmlContent = await htmlResponse.text();
	    $('h1.parameters').append(htmlContent);

	    const apiResponse = await fetch('/api/v1/contrib/changerules/config');
	    if (!apiResponse.ok)
		throw new Error('error while fetching changerules config');

	    const data = await apiResponse.json();
	    if ( !data.start_date || !data.end_date )
		return;

	    changeDisplay(data.start_date, data.end_date);
	}
	catch {
	    console.error('Error fetching ressources :', error);
	};
    }
});
