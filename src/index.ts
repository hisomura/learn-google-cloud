import { Request, Response } from "express";

const html = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>URL Test</title>
</head>
<body>
Your Request HEADERS
<p>
  <pre>
    __REQUEST_HEADER__
  </pre>
</p>
</body>
</html>
`;
exports.helloWorld = (req: Request, res: Response) => {
  res.set("Content-Type", "text/html; charset=UTF-8");
  console.log(req)
  const {headers, url, baseUrl, originalUrl} = req
  const data = {headers, url, baseUrl, originalUrl}
  res.send(html.replace('__REQUEST_HEADER__', JSON.stringify(data, null, 2)));
};
