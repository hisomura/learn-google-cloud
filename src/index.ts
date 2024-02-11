import { Response } from "express";

const html = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Title</title>
</head>
<body>
Hello, World!
</body>
</html>
`;
exports.helloWorld = (req: any, res: Response) => {
  res.set("Content-Type", "text/html; charset=UTF-8");
  res.send(html);
};
