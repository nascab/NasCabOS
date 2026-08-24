const tmdbUtil = require('./tmdbUtil');
let text = '[电影天堂www.dytt8899.com]我会好好的-2025_HD国语中英双字-fanart';
const { tokens, year } = tmdbUtil.getSearchTokens(text);
console.log(tokens, year);
